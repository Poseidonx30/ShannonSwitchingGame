const TEAM_NAME::String = "StockFisch 1.0"

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)


function weighted_cut(state::GameState)::Edge 
    if length(state.history) == 1 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(Vector{Vertex}(), Vector{Edge}(), state.graph.s, state.graph.t)
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Vector{Int}(), Vector{Int}(), Dict{Int, Int}(), Vector{Int}()), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :cut, false, Base.Set{Edge}(), nothing)
    end 
    if EXTENDED_STATE[].winner != :cut  #noch nicht gewonnen (im aktuellen merged graph, nicht allgemein)
        EXTENDED_STATE[].winner = (check_st_connection(EXTENDED_STATE[].merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  #schon gewonnen (im aktuellen merged graph sind s und t nicht mehr verbunden)
        return rand(valid_moves(state))
    end 

    if EXTENDED_STATE[].has_winning_strategy == :cut
        return chase(EXTENDED_STATE[], state)
    else 
        shorts_edge = state.history[end][2]
        merged_graph = EXTENDED_STATE[].merged_graph
        if !(get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t.id) 
            || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t.id))
            merge_components!(merged_graph.components, shorts_edge.u.id, shorts_edge.v.id)  #neue Zusammenhangskomponenten setzen; s und t sollen nicht in einem Zshk. kommen
        end 
        delete!(merged_graph.edges, shorts_edge)
        who_can_win(EXTENDED_STATE[], false)
        if EXTENDED_STATE[].has_winning_strategy == :cut  #false, da für cut Gewichtung nicht interessant, falls optimale Strategie existiert (sofern Strafe für short hoch genug - hoffe ich mal)
            EXTENDED_STATE[].first_optimal_move = true 
            return chase(EXTENDED_STATE[], state)
        else
            println("hallo")
            cuts_edge = MCTS(EXTENDED_STATE[], state)
            delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
            return cuts_edge
        end 
    end 
end

mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Base.Set{MCTS_node}
    total_weight_at_end::Float64
    visits::Int
    short_graph::GameGraph
    short_merged_graph::EfficientGameGraph
    current_player::Symbol
    terminal::Bool
    untried_actions::Base.Set{Edge} # der Wert gibt an, ob der Zug noch verfügbar ist
end

function MCTS(state::ExtendedGameState, orig_state::GameState; time_limit = 1.0)::Edge # state.graph muss die von short beanspruchten Kanten enthalten, WICHTIG: die Zusammenhangskomponenten von ComponentTracker müssen berichtigt werden, wenn der Anfangsgraph nicht-leer ist
    start_time = time()
    root_node = MCTS_node(nothing, Base.Set(), Inf, 0, state.short_graph, state.merged_graph, :short, false, Base.Set(valid_moves(orig_state)))
    while true
        if time() - start_time >= time_limit
            println("Limit erreicht")
            break 
        end
        println("stuck")
        node = select(root_node)
        if node.terminal
            println("schlecht")
            backpropagate!(node, node.weight_at_end)
        end
        println("hallo-2"); flush(stdout)
        new_node = expand!(node)
        println("hallo-1"); flush(stdout)
        if new_node[2] != -Inf # dann ist der expandierte Zustand ein Endzustand
            println("hallo1");flush(stdout)
            backpropagate!(new_node[1], new_node[2])
            println("hallo2"); flush(stdout)
        end
        println("hallo2"); flush(stdout)
        node = simulate!(node)
        println("hallo3"); flush(stdout)
        backpropagate!(node[1], node[2])
        println("hallo4"); flush(stdout)
    end
    ucb = -Inf
    max_child = nothing
    for child in root_node.children
        if child.visits != 0 && -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits)) > ucb
            max_child = child
            ucb = -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits))
        end
    end
    return setdiff(max_child.parent.short_graph.edges, max_child.short_graph.edges)
end 

@inline function select(node::MCTS_node)::MCTS_node
    current_node = node
    # möglicherweise noch nicht besuchte Kinder bevorzugen
    while !isempty(current_node.children)
        ucb = -Inf
        max_child = nothing
        found_node = false
        for child in current_node.children
            if child.visits == 0
                current_node = child
                found_node = true
                break
            elseif -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits)) > ucb # child.visits ≠ 0
                max_child = child
                ucb = -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits))
            end
        end
        if !found_node
            current_node = max_child
        end
    end
    return current_node
end

@inline function expand!(node::MCTS_node)::Tuple{MCTS_node,Float64}
    new_node = nothing
    terminal = false
    if node.current_player == :short && get_component!(node.short_merged_graph.components, node.short_merged_graph.s.id) == get_component!(node.short_merged_graph.components, node.short_merged_graph.t.id) # dann haben wir schon einen s-t-Weg
        random_move = rand(collect(node.untried_actions)) # vielleicht noch nach Kantengewichten sortieren
        new_graph = copy(node.short_graph)
        push!(new_graph.edges, random_move)
        new_efficient_graph = copy(node.short_merged_graph)
        merge_components!(new_efficient_graph.components, random_move.u.id, random_move.v.id)
        new_untried_actions = Base.setdiff(node.untried_actions, [random_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, false, new_untried_actions)
        push!(node.children, new_node)
    elseif node.current_player == :short # wir suchen einen Zug, der zwei neue Zusammenhangskomponenten verbindet
        next_move = nothing
        for edge in node.untried_actions
            if get_component!(node.short_merged_graph.components, edge.u.id) != get_component!(node.short_merged_graph.components, edge.v.id) # falls die Kante zwei neue Zusammenhangskomponente verbindet # get_component!(node.short_merged_graph.components, node.graph.s.id) == get_component!(node.short_merged_graph.components, edge.u.id) && 
                next_move = edge
                break
            end
        end
        new_graph = copy(node.short_graph)
        push!(new_graph.edges, next_move)
        new_efficient_graph = copy(node.short_merged_graph)
        merge_components!(new_efficient_graph.components, next_move.u.id, next_move.v.id)
        new_untried_actions = Base.setdiff(node.untried_actions, [next_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, new_graph, new_efficient_graph, :cut, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, new_graph, new_efficient_graph, :cut, false, new_untried_actions)
        push!(node.children, new_node)
    elseif node.current_player == :cut # zunächst angenommen, dass cut random züge spielt
        # vielleicht noch optimieren, dass wenn s und t nicht in unterschiedlichen Zusammenhangskomponenten sind, das Spiel vorzeitig terminiert (short kassiert sowieso die Strafe)
        random_move = rand(collect(node.untried_actions))
        new_untried_actions = Base.setdiff(node.untried_actions, [random_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, copy(node.short_graph), copy(node.short_merged_graph), :short, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, copy(node.short_graph), copy(node.short_merged_graph), :short, false, new_untried_actions)
        push!(node.children, new_node)
    end
    return (new_node,-Inf)
end

@inline function simulate!(node::MCTS_node)::Tuple{MCTS_node,Float64} # gibt den teminalen Knoten zurück sowie das minimale Gewicht eines s-t-Weges
    current_node = node
    while !current_node.terminal
        new_node = nothing
        if current_node.current_player == :short
            random_move = rand(collect(current_node.untried_actions))
            new_graph = copy(current_node.short_graph)
            push!(new_graph.edges, random_move)
            new_efficient_graph = copy(current_node.short_merged_graph)
            merge_components!(new_efficient_graph.components, random_move.u.id, random_move.v.id)
            new_untried_actions = Base.setdiff(current_node.untried_actions, [random_move])
            terminal = isempty(new_untried_actions)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, new_graph, new_efficient_graph, :cut, terminal, new_untried_actions)
            push!(current_node.children, new_node)
        else
            random_move = rand(collect(current_node.untried_actions))
            new_untried_actions = Base.setdiff(current_node.untried_actions, [random_move])
            terminal = isempty(new_untried_actions)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), Inf, 0, copy(current_node.short_graph), copy(current_node.short_merged_graph), :short, terminal, new_untried_actions)
            push!(current_node.children, new_node)
        end
        current_node = new_node
    end
    return (current_node, dijkstra(current_node.short_graph, current_node.short_graph.s, current_node.short_graph.t))
end

@inline function backpropagate!(node::MCTS_node, weight_at_end::Int)
    current_node = node
    while !isnothing(node.parent) # wird immer mit mindestens Kindknoten von root aufgerufen
        current_node.total_weight_at_end += weight_at_end
        current_node.visits += 1
        current_node = current_node.parent
    end
end