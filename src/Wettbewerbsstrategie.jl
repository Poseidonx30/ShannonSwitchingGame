const TEAM_NAME::String = "StockFisch 1.2"

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)

function weighted_cut(state::GameState)::Edge
    start_time = time() 
    if length(state.history) == 1 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(Vector{Vertex}(), Vector{Edge}(), state.graph.s, state.graph.t)
        short_graph.vertices = state.graph.vertices
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Int[]), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :cut, false, Base.Set{Edge}(), nothing)
    end 
    shorts_edge = state.history[end][2]
    short_graph = EXTENDED_STATE[].short_graph
    push!(short_graph.edges, shorts_edge) # die letzte Kante von short wird in den short_graph eingefügt, damit die Zusammenhangskomponenten korrekt sind  
    if EXTENDED_STATE[].winner != :cut  #noch nicht gewonnen (im aktuellen merged graph, nicht allgemein)
        EXTENDED_STATE[].winner = (check_st_connection(EXTENDED_STATE[].merged_graph) == false) ? :cut : nothing
        if EXTENDED_STATE[].winner == :cut
            for edge in short_graph.edges 
                delete!(EXTENDED_STATE[].merged_graph.edges, edge)
                merge_components!(EXTENDED_STATE[].merged_graph.components, edge.u.id, edge.v.id)
            end 
        end 
    end
    if EXTENDED_STATE[].winner == :cut  #schon gewonnen (im aktuellen merged graph sind s und t nicht mehr verbunden)
        end_time = time()   
        cuts_edge = MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time))
        delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
        return cuts_edge
    end 
    if EXTENDED_STATE[].has_winning_strategy == :cut
        cuts_edge = chase(EXTENDED_STATE[], state)
    else 
        merged_graph = EXTENDED_STATE[].merged_graph
        if !(get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t.id) 
            || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t.id))
            merge_components!(merged_graph.components, shorts_edge.u.id, shorts_edge.v.id)  #neue Zusammenhangskomponenten setzen; s und t sollen nicht in einem Zshk. kommen
        end 
        delete!(merged_graph.edges, shorts_edge)
        who_can_win(EXTENDED_STATE[], false)
        if EXTENDED_STATE[].has_winning_strategy == :cut  #false, da für cut Gewichtung nicht interessant, falls optimale Strategie existiert (sofern Strafe für short hoch genug - hoffe ich mal)
            EXTENDED_STATE[].first_optimal_move = true 
            cuts_edge = chase(EXTENDED_STATE[], state)
        else
            end_time = time()   
            cuts_edge = MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time))
        end 
    end 
    delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
    return cuts_edge
end

function weighted_short(state::GameState)::Edge
    start_time = time()
    len = length(state.history)
    if len == 0 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(Vector{Vertex}(), Vector{Edge}(), state.graph.s, state.graph.t)
        short_graph.vertices = state.graph.vertices
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Int[]), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :short, false, Base.Set{Edge}(), nothing)
    end 
    merged_graph = EXTENDED_STATE[].merged_graph
    if len !=0
        shorts_old_edge = state.history[end-1][2]
        delete!(merged_graph.edges, state.history[end][2])   #######
        delete!(merged_graph.edges, shorts_old_edge)
        merge_components!(merged_graph.components, shorts_old_edge.u.id, shorts_old_edge.v.id)

        short_graph = EXTENDED_STATE[].short_graph
        push!(short_graph.edges, shorts_old_edge) # die letzte Kante von short wird in den short_graph eingefügt, damit die Zusammenhangskomponenten korrekt sind
    end
    end_time = time()
    shorts_edge = MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time)) 
    return shorts_edge
end

mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Vector{MCTS_node}
    total_weight_at_end::Float64
    visits::Int
    current_player::Symbol
    terminal::Bool
    last_move::Union{Nothing,Edge}
end


function MCTS(state::ExtendedGameState, orig_state::GameState; time_limit = 1.0)::Edge # state.graph muss die von short beanspruchten Kanten enthalten, WICHTIG: die Zusammenhangskomponenten von ComponentTracker müssen berichtigt werden, wenn der Anfangsgraph nicht-leer ist
    start_time = time()
    root_node = MCTS_node(nothing, Vector{MCTS_node}(), 0.0, 0, orig_state.current_player, false, nothing)
    s_component = get_component!(state.merged_graph.components, state.merged_graph.s.id)
    t_component = get_component!(state.merged_graph.components, state.merged_graph.t.id)
    short_graph = state.short_graph
    short_merged_graph = state.merged_graph

    save_base_state!(state.merged_graph.components)
    ws = DijkstraWorkspace(50)
    untried_actions = Vector{Edge}()
    sizehint!(untried_actions, length(state.merged_graph.edges))
    #iterations = 0
    while true
        if time() - start_time >= time_limit
            break 
        end
        empty!(untried_actions)
        for edge in state.merged_graph.edges
            if get_component!(state.merged_graph.components, edge.u.id) == s_component || 
               get_component!(state.merged_graph.components, edge.v.id) == s_component || 
               get_component!(state.merged_graph.components, edge.u.id) == t_component || 
               get_component!(state.merged_graph.components, edge.v.id) == t_component
           
               push!(untried_actions, edge)
            end
        end
        if isempty(untried_actions)
            append!(untried_actions, valid_moves(orig_state))
        end
        root_node.visits += 1
        node = select(root_node, short_graph, short_merged_graph, untried_actions)
        if node.terminal
            backpropagate!(node, node.total_weight_at_end / (node.visits - 1), short_graph, short_merged_graph)
            restore_base_state!(state.merged_graph.components)
            #iterations += 1
            continue
        end
        node = expand!(node, short_graph, short_merged_graph, untried_actions, ws)
        if node[2] != -1 # dann ist der expandierte Zustand ein Endzustand
            backpropagate!(node[1], node[2], short_graph, short_merged_graph)
            restore_base_state!(state.merged_graph.components)
            #iterations += 1
            continue
        end
        weight = simulate!(node[1], short_graph, short_merged_graph, untried_actions, ws)
        backpropagate!(node[1], weight, short_graph, short_merged_graph)
        restore_base_state!(state.merged_graph.components)
        #iterations += 1
    end
    #println("Der Computer hat ", iterations, " viele Iterationen geschafft.")
    max_child = argmax(x -> x.visits, root_node.children)
    return max_child.last_move
end 

function select(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge})::MCTS_node
    current_node = node
    while !isempty(current_node.children)
        local_q_min = Inf
        local_q_max = -Inf
        
        for child in current_node.children
            if child.visits > 0
                q = child.total_weight_at_end / child.visits
                if q < local_q_min
                    local_q_min = q
                end
                if q > local_q_max
                    local_q_max = q
                end
            end
        end

        span = local_q_max - local_q_min

        ucb = -Inf
        max_child = nothing
        found_node = false
        log_parent_visits = log(current_node.visits)
        is_short = current_node.current_player == :short
     
        for child in current_node.children
            if child.visits == 0 # nur wichtig, wenn wir in einem Schritt mehrere Knoten expanden
                make_move!(short_graph, short_merged_graph, untried_actions, child.last_move, current_node.current_player)
                current_node = child
                found_node = true
                break
            end 

            exploration = sqrt(2.0 * log_parent_visits / child.visits)
            exploitation = child.total_weight_at_end / child.visits
            
            if span > 1e-8
                q_norm = (exploitation - local_q_min) / span
            else
                q_norm = 0.5 # Neutraler Startwert, wenn alle Pfade (bisher) denselben Durchschnitt haben
            end
 
            if is_short
                val = (1.0 - q_norm) + exploration
            else
                val = q_norm + exploration
            end

            if val > ucb
                max_child = child
                ucb = val
            end
        end
        if !found_node
            make_move!(short_graph, short_merged_graph, untried_actions, max_child.last_move, current_node.current_player)
            current_node = max_child
        end
        current_node.visits += 1
    end
    return current_node
end

function expand!(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace)::Tuple{MCTS_node,Float64}
    new_node = nothing
    terminal = false
    idx = rand(1:length(untried_actions))
    next_move = untried_actions[idx]
    next_player = node.current_player == :short ? :cut : :short
    if length(untried_actions) > 1 # andernfalls wird unten schon der letzte mögliche Zustand eingefügt
        for i in 1:length(untried_actions)
            if i == idx
                continue
            end
            push!(node.children, MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, next_player, false, untried_actions[i]))
        end
    end
    if node.current_player == :short
        make_move!(short_graph, short_merged_graph, untried_actions, idx, :short) # führe Zug auf übergebenen Bäumen aus #idx vlt
        terminal = isempty(untried_actions)
        if terminal
            weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
            new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 1, :cut, true, next_move)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, :cut, false, next_move)
        push!(node.children, new_node)
    elseif node.current_player == :cut # zunächst angenommen, dass cut random züge spielt
        make_move!(short_graph, short_merged_graph, untried_actions, idx, :cut)
        terminal = isempty(untried_actions)
        if terminal
            weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
            new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 1, :short, true, next_move)
            push!(node.children, new_node)
            return (new_node, weight)
        end 
        new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, :short, false, next_move)
        push!(node.children, new_node)
    end
    new_node.visits += 1
    return (new_node,-1)
end

function simulate!(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace)::Float64 # gibt das minimale Gewicht eines s-t-Weges zurück
    current_player = node.current_player
    simulated_moves = Tuple{Edge, Symbol}[] 
    while !isempty(untried_actions)
        idx = rand(1:length(untried_actions))
        push!(simulated_moves, (untried_actions[idx], current_player))
        make_move!(short_graph, short_merged_graph, untried_actions, idx, current_player)
        current_player = current_player == :short ? :cut : :short
    end
    weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
    for i in length(simulated_moves):-1:1
        move, player = simulated_moves[i]
        undo_move!(short_graph, short_merged_graph, move, player)
    end
    return weight
end

function backpropagate!(node::MCTS_node, weight_at_end::Float64, short_graph::GameGraph, short_merged_graph::EfficientGameGraph)
    current_node = node
    while !isnothing(current_node) # wird immer mit mindestens Kindknoten von root aufgerufen
        current_node.total_weight_at_end += weight_at_end

        if !isnothing(current_node.parent)
            undo_move!(short_graph, short_merged_graph, current_node.last_move, current_node.parent.current_player)
        end
        
        current_node = current_node.parent
    end
end

function make_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, move::Edge, player::Symbol)
    if player == :short
        push!(short_graph.edges, move)
        merge_components!(short_merged_graph.components, move.u.id, move.v.id)
        delete!(short_merged_graph.edges, move)
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
        s_component = get_component!(short_merged_graph.components, short_merged_graph.s.id)
        t_component = get_component!(short_merged_graph.components, short_merged_graph.t.id)
        for edge in short_merged_graph.edges
            if (get_component!(short_merged_graph.components, edge.u.id) == s_component || get_component!(short_merged_graph.components, edge.v.id) == s_component || get_component!(short_merged_graph.components, edge.u.id) == t_component || get_component!(short_merged_graph.components, edge.v.id) == t_component) && !any(x -> x.id == edge.id, untried_actions)
                push!(untried_actions, edge)
            end
        end
    else
        delete!(short_merged_graph.edges, move)
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function make_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, move_pos::Int, player::Symbol)
    if player == :short
        push!(short_graph.edges, untried_actions[move_pos]) 
        merge_components!(short_merged_graph.components, untried_actions[move_pos].u.id, untried_actions[move_pos].v.id)
        delete!(short_merged_graph.edges, untried_actions[move_pos])
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
        s_component = get_component!(short_merged_graph.components, short_merged_graph.s.id)
        t_component = get_component!(short_merged_graph.components, short_merged_graph.t.id)
        for edge in short_merged_graph.edges
            if (get_component!(short_merged_graph.components, edge.u.id) == s_component || get_component!(short_merged_graph.components, edge.v.id) == s_component || get_component!(short_merged_graph.components, edge.u.id) == t_component || get_component!(short_merged_graph.components, edge.v.id) == t_component) && !any(x -> x.id == edge.id, untried_actions)
                push!(untried_actions, edge)
            end
        end
    else
        delete!(short_merged_graph.edges, untried_actions[move_pos])
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function undo_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, move::Edge, player::Symbol)
    if player == :short
        pos = findfirst(x->x.id == move.id, short_graph.edges)
        short_graph.edges[pos] = short_graph.edges[end]
        pop!(short_graph.edges)
        push!(short_merged_graph.edges, move)
    else
        push!(short_merged_graph.edges, move)
    end
end