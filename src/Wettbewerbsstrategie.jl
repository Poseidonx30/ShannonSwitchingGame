const TEAM_NAME::String = "StockFisch 1.0"

mutable struct ExtendedGameState
    graph::EfficientGameGraph
    short_graph::EfficientGameGraph
    merged_graph::EfficientGameGraph
    A::Base.Set{Edge} 
    B::Base.Set{Edge} 
    e1::Edge
    has_winning_strategy::Symbol
    current_player::Symbol
    history::Vector{Tuple{Symbol, Edge}} 
    imaginary_moves::Base.Set{Edge}
    winner::Union{Symbol, Nothing}
end

mutable struct EfficientGameGraph
    edges::Base.Set{Edge}  
    zusammenhangskomponenten::Dict{Vertex,customSet}() #zum Effizienten Umgang mit merged_graph
    s::Vertex                 
    t::Vertex                 
end

mutable struct Element
    value::Vertex
    parent::Any
    s::Union{Element,Nothing}
end

mutable struct customSet
    head::Element
    tail::Element
    size::Int
end

function make_set(elem::Element)::customSet
    newSet = customSet(elem, elem, 1)
    elem.parent = newSet
    return newSet
end

function find_set(elem::Element)::customSet
    return elem.parent
end


function union!(elem1::Element, elem2::Element)::Element
    if elem1.parent.size < elem2.parent.size # hänge Liste2 an Liste1, falls Liste2 länger ist, vertausche die Listen
        temp = elem1
        elem1 = elem2
        elem2 = temp
    end
    parent2 = elem2.parent
    elem1.parent.size += parent2.size
    elem1.parent.tail.s = parent2.head
    if !isnothing(parent2.tail.s)
        nothing
    end
    currentElement = parent2.head
    while !isnothing(currentElement)
        if isnothing(currentElement.s)
            elem1.parent.tail = currentElement
        end
        currentElement.parent = elem1.parent
        currentElement = currentElement.s
    end
    return parent2.head
end

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)

function check_st_connection(G::EfficientGameGraph)::Bool #Adaption von kruskal über union find
    sets = copy(Dict{Vertex,customSet}())
    for e in G.edges
        if sets[G.t] == sets[G.s]
            return true
        end 
        if sets[e.u] !== sets[e.v]
           deletedSet = union!(sets[e.u].tail, sets[e.v].head)
           delete!(sets, deletedSet.value)
        end 
    end 
    return false
end 

function merge_graph!(e::Edge)
    
end

function weighted_short(state::GameState)::Edge

end

function weighted_cut(state::GameState)::Edge 
    if length(state.history) == 1
        graph = EfficientGameGraph(Base.Set(state.graph.edges), Base.Set{customSet}(), state.graph.s, state.graph.t) 
        short_graph = EfficientGameGraph(Base.Set(history[end][2]), Base.Set{customSet}(), state.graph.s, state.graph.t)
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), Base.Set{customSet}([make_set(Element(v, nothing, nothing)) for v in state.graph.vertices]), state.graph.s, state.graph.t) #anpassen für Dict
        A = Base.Set{Edge}()
        B = Base.Set{Edge}()
        e1 = Edge(Inf, state.graph.s, state.graph.t)
        EXTENDED_STATE[] = ExtendedGameState(graph, short_graph, merged_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, :neutral, :cut, copy(state.history), Base.Set{Edge}(), nothing)
    end 
    if EXTENDED_STATE[].winner != :cut  #noch nicht gewonnen (im aktuellen merged graph, nicht allgemein)
        EXTENDED_STATE[].winner = (check_st_connection(merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  #schon gewonnen (im aktuellen merged graph sind s und t nicht mehr verbunden)
        return rand(valid_moves(state))
    end 
    merge_graph!(state.history[end][2])  #neue Zusammenhangskomponenten setzen
end

function MCTS(state::GameState; Zeitlimit = 1.0)
     
end 


