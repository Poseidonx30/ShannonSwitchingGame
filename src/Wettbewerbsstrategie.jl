const TEAM_NAME::String = "StockFisch 1.0"

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)


function weighted_cut(state::GameState)::Edge 
    if length(state.history) == 1 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Vector{Int}(), Vector{Int}(), Dict{Int, Int}(), Vector{Int}()), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, :neutral, :cut, false, Base.Set{Edge}(), nothing)
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
            cuts_edge = rand(valid_moves(state)) #MCTS
            delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
            return cuts_edge
        end 
    end 
end

#= mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Base.Set{MCTS_node}
    total_weight_at_end::Int
    visits::Int
    graph::GameGraph
    s::Node
    t::Node
    untried_actions::Vector{Edge}
    terminal::Bool
end =#

#= function MCTS(state::GameState; time_limit = 1.0)::Union{Nothing,Edge}
    try
        @async begin # nach Ablauf von time_limit wird ein error geworfen
            sleep(time_limit)
            throw(InterruptException())
        end
        if !isnothing(state.winner)
            return nothing
        end
        untried_actions = valid_moves(state)
        root_node = MCTS_node(nothing, Base.Set(), 0.0, 0, untried_actions, false)
        while true
            expand(select(root_node))
    catch e
        if !isa(e, InterruptException)
            println("Nicht geplantes Verhalten")
        end
    end
end 

@inline function select(node::MCTS_node)::MCTS_node
    current_node = node
    # möglicherweise noch nicht besuchte Kinder bevorzugen
    while !isnothing(current_node.children)
        ucb = -∞
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

@inline function expand(node::MCTS_node)::Union{Nothing,Float64}
    random_move = popat!(node.untried_actions, floor(rand()*length(node.untried_actions)))
    is_terminal = isempty(node.untried_actions)
    if is_terminal
        weight = dijkstra(node.graph, node.s, node.t)
        return weight
    end
    push!(node.children, MCTS_node(node, Base.Set(), 0.0, 0, node.untried_actions, isempty(node.untried_actions)))
    return nothing
end

@inline function backpropagate!(node::MCTS_node, weight_at_end::Int)
    while !isnothing(node.parent) # wird immer mit mindestens Kindknoten von root aufgerufen
        node.total_weight_at_end += weight_at_end
        node.visits += 1
        node = node.parent
    end
end =#