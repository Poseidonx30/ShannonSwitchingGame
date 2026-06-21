mutable struct Vertex
    id::Int 
end

mutable struct Edge 
    id::Int
    u::Vertex   #von u nach v 
    v::Vertex
    weight::Float64
    state::Symbol # :neutral, :short, :cut
end 

mutable struct GameGraph
    vertices::Vector{Vertex}
    edges::Vector{Edge}
    s::Vertex
    t::Vertex
end

mutable struct GameState
    graph::GameGraph
    short_Graph::GameGraph
    A::GameGraph # Aufspannende Bäume für Short Strategie
    B::GameGraph #
    A_cut::GameGraph #Disjunkte Kantenmengen für 
    B_cut::GameGraph
    current_player::Symbol
    history::Vector{Tuple{Symbol, Edge}}
    winner::Union{Symbol, Nothing}
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

function union(elem1::Element, elem2::Element)::Element
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

function new_game(g::GameGraph)::GameState
    short_Graph = GameGraph([g.s, g.t], Vector{Edge}(), g.s, g.t)
    A = GameGraph([g.s, g.t], Vector{Edge}(), g.s, g.t)
    B = GameGraph([g.s, g.t], Vector{Edge}(), g.s, g.t)
    return GameState(g, short_Graph, A, B, A, B, :short, Vector{Tuple{Symbol, Edge}}(), nothing)
end

function valid_moves(state::GameState)::Vector{Edge}
    return filter(e -> e.state == :neutral, state.graph.edges)
end

function make_move!(state::GameState, e::Edge)::Nothing
    (e ∉ valid_moves(state)) && return nothing
    push!(state.history, (state.current_player, e))
    if state.current_player == :short 
        push!(state.short_Graph.edges, e)
        if e.u ∉ [state.graph.t, state.graph.s]
            push!(state.short_Graph.vertices, e.u)
        end
        if e.v ∉ [state.graph.t, state.graph.s]
            push!(state.short_Graph.vertices, e.v)
        end
        e.state = :short
        state.winner = check_winner(state)
        state.current_player = :cut
    else
        new_Game_Graph_edges = [edge for edge in state.graph.edges if (edge !== e)]
        state.graph.edges = new_Game_Graph_edges
        e.state = :cut
        state.winner = check_winner(state)
        state.current_player = :short
    end
    return nothing
end

function check_winner(state::GameState)::Union{Symbol, Nothing}
    if state.current_player == :short
        check_st_connection(state.short_Graph) && return :short
    else 
        !(check_st_connection(state.graph)) && return :cut
    end
    return nothing 
end 

function random_graph(n::Int, m::Int; weighted=false)::Union{GameGraph, Nothing} #n: Anzahl Knoten, m:Anzahl Kanten
    if m < n || n <= 3 || m >= n*(n-1)/2 || m >= 2*n
        println("Langweilig! Wähle mindestens n Kanten und mindestens 4 Knoten aber nicht zu viele Kanten")
        return nothing 
    elseif weighted == false
        Anzahl_Fundamentale_Wege = rand(2:1:min(m-n+2, floor(Int, m/2), n-2))
        Knoten = [Vertex(i) for i in 1:1:n]
        s = Knoten[1]
        t = Knoten[n]
        Anzahl_Knoten_auf_fundamentalen_Wegen = Vector{Int}()
        Anzahl_verbleibende_Knoten = n-2-Anzahl_Fundamentale_Wege
        for j in 1:1:Anzahl_Fundamentale_Wege
            if Anzahl_verbleibende_Knoten ≥ 1
               k = rand(1:1:Anzahl_verbleibende_Knoten)
               push!(Anzahl_Knoten_auf_fundamentalen_Wegen, k+1)
               Anzahl_verbleibende_Knoten -= k
            else 
                push!(Anzahl_Knoten_auf_fundamentalen_Wegen, 1)
            end
        end 
        Kanten_id = 1
        Edges = Vector{Edge}()
        for i in 1:1:Anzahl_Fundamentale_Wege
            prev = s
            current = Knoten[2 + sum([Anzahl_Knoten_auf_fundamentalen_Wegen[k] for k in 1:1:(i-1)])] 
            for j in 1:1:Anzahl_Knoten_auf_fundamentalen_Wegen[i]
                push!(Edges, Edge(Kanten_id, prev, current, 0.0, :neutral))
                Kanten_id += 1
                prev = current 
                current = Knoten[2 + sum([Anzahl_Knoten_auf_fundamentalen_Wegen[k] for k in 1:1:(i-1)]) + j]
            end 
            push!(Edges, Edge(Kanten_id, prev, t, 0.0, :neutral))
            Kanten_id += 1
        end  
        used = Base.Set{Tuple{Int,Int}}()
        for edge in Edges 
            push!(used, (min(edge.u.id, edge.v.id), max(edge.u.id, edge.v.id)))
        end
        k = 1
        while length(Edges) < m && k <= 4*m
            k += 1
            i = rand(2:n-1)
            j = rand(setdiff(2:n-1, [i]))
            a, b = min(i, j), max(i, j)
            if (a, b) in used
               continue
            end
            push!(used, (a, b))
            push!(Edges, Edge(Kanten_id, Knoten[i], Knoten[j], 0.0, :neutral))
            Kanten_id += 1
        end  
        if length(Edges) < m
            for j in length(Edges)+1:m
                i = rand(2:n-1)
                j = rand(setdiff(2:n-1, [i]))
                push!(Edges, Edge(Kanten_id, Knoten[i], Knoten[j], 0.0, :neutral))
                Kanten_id += 1
            end
        end
        return GameGraph(Knoten, Edges, s, t)
    else 
        println("Coming soon!")
    end
                  
end

function check_st_connection(graph::GameGraph)::Bool
    queue = Vector{Vertex}()
    visited = Dict{Int,Vertex}()
    pushfirst!(queue, graph.s)
    while length(queue) != 0
        currentElement = popfirst!(queue)
        merge!(visited, Dict(currentElement.id => currentElement))
        newVertices = Vector{Vertex}()
        for i ∈ eachindex(graph.edges)
            if graph.edges[i].u === currentElement
                if graph.edges[i].v === graph.t
                    return true
                elseif get(visited, graph.edges[i].v.id, -1) == -1
                    push!(newVertices, graph.edges[i].v)
                end
            elseif graph.edges[i].v === currentElement
                if graph.edges[i].u === graph.t
                    return true
                elseif get(visited, graph.edges[i].u.id, -1) == -1
                    push!(newVertices, graph.edges[i].u)
                end
            end
        end
        append!(queue, newVertices)
    end
    return false
end
