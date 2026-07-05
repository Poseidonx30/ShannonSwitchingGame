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
    A::Base.Set{Edge} 
    B::Base.Set{Edge} 
    e1::Edge
    e2::Edge
    has_winning_strategy::Symbol
    current_player::Symbol
    history::Vector{Tuple{Symbol, Edge}}
    imaginary_moves::Base.Set{Edge}
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

function _make_set(elem::Element)::customSet
    newSet = customSet(elem, elem, 1)
    elem.parent = newSet
    return newSet
end

function _find_set(elem::Element)::customSet
    return elem.parent
end

function _union(elem1::Element, elem2::Element)::Element
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

"""
    new_game(g::GameGraph)::GameState

Erstellt eine neue Spielinstanz mit dem Spielfeld (Graphen) g.

# Beispiel
```julia
julia> g = random_graph(4,5);

julia> new_game(g);
```
"""
function new_game(g::GameGraph)::GameState
    short_Graph = GameGraph([g.s, g.t], Vector{Edge}(), g.s, g.t)
    A = Base.Set{Edge}()
    B = Base.Set{Edge}()
    return GameState(g, short_Graph, A, B, Edge(0, g.s, g.t, 0.0, :neutral), Edge(0, g.s, g.t, 0.0, :neutral), :neutral, :short, Vector{Tuple{Symbol, Edge}}(), Base.Set{Edge}(), nothing)
end

"""
    valid_moves(state::GameState)::Vector{Edge}

Gibt alle im Spielzustand state zulässigen Züge zurück (entspricht allen verbleind).

# Beispiel
```julia
julia> g = random_graph(4,5);

julia> state = new_game(g);

julia> valid_moves(state)
5-element Vector{ShannonSwitchingGame.Edge}:
 ShannonSwitchingGame.Edge(1, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)
 ShannonSwitchingGame.Edge(2, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(3, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(3), 0.0, :neutral)
 ShannonSwitchingGame.Edge(4, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(5, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)
```
"""
function valid_moves(state::GameState)::Vector{Edge}
    return filter(e -> e.state == :neutral, state.graph.edges)
end

"""
    make_move!(state::GameState, e::Edge)::Nothing

Spielt den Zug e (falls dieser ein zulässiger Zug im Zustand state ist) im GameState state. Dabei wird auch der aktuelle Spieler auf den jeweils anderen Spieler gesetzt. Ist der aktuelle Spieler cut, so wird der Zug e zusätzlich zu state.short_graph hinzugefügt. Andernfalls wird der Zug aus state.graph gelöscht. Zuletzt wird noch geprüft, ob einer der Spieler nach Ausführen des Zugs e gewonnen hat. Ist dies der Fall, setzen wir entsprechend state.winner.

# Beispiel
```julia
julia> g = random_graph(4,5); state = new_game(g); moves = valid_moves(state)
5-element Vector{ShannonSwitchingGame.Edge}:
 ShannonSwitchingGame.Edge(1, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)
 ShannonSwitchingGame.Edge(2, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(3, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(3), 0.0, :neutral)
 ShannonSwitchingGame.Edge(4, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(5, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)

julia> make_move!(state, moves[1]);

julia> valid_moves(state)
4-element Vector{ShannonSwitchingGame.Edge}:
 ShannonSwitchingGame.Edge(2, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(3, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(3), 0.0, :neutral)
 ShannonSwitchingGame.Edge(4, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4), 0.0, :neutral)
 ShannonSwitchingGame.Edge(5, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(3), 0.0, :neutral)
```
"""
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

"""
    check_winner(state::GameState)::Union{Symbol, Nothing}

Überprüft, ob im Zustand state der aktuelle Spieler gewonnen hat, also short einen s-t-Weg gebildet hat oder cut so gepielt hat, dass s und t in verschiedenen Zusammenhangskomponenten sind. Hat keiner der beiden Spieler gewonnen, gibt die Funktion nothing zurück.

# Beispiel
```julia
julia> g = random_graph(4,5);

julia> state = new_game(g);

julia> check_winner(state) # gibt nothing zurück

```
"""
function check_winner(state::GameState)::Union{Symbol, Nothing}
    if state.current_player == :short
        _check_st_connection(state.short_Graph) && return :short
    else 
        !(_check_st_connection(state.graph)) && return :cut
    end
    return nothing 
end 

"""
    random_graph(n::Int, m::Int; weighted=false)::Union{GameGraph, Nothing}

Erstellt einen pseudo-zufälligen zusammenhängenden Graphen mit n Knoten und m Kanten. Der Parameter weighted gibt an, ob die Kanten mit Gewichten aus dem Interall [1,10] initialisiert werden sollen. Ist weighted==false werden alle Kantengewichte mit 0.0 initialisiert.

Der Graph sollte mindestens 4 Knoten haben und nicht mehr als 2n-1 Kanten (sonst kann short immer gewinnen). Weiterhin muss m ≥ n sein, sonst ist der Graph nicht zusammenhängend.

# Beispiel
```julia
julia> g = random_graph(4,5)
ShannonSwitchingGame.GameGraph(ShannonSwitchingGame.Vertex[ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4)], ShannonSwitchingGame.Edge[ShannonSwitchingGame.Edge(1, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), 0.0, :neutral), ShannonSwitchingGame.Edge(2, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(4), 0.0, :neutral), ShannonSwitchingGame.Edge(3, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(3), 0.0, :neutral), ShannonSwitchingGame.Edge(4, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4), 0.0, :neutral), ShannonSwitchingGame.Edge(5, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)], ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(4))

julia> g_ewichtet = random_graph(4,5; weighted=true)
ShannonSwitchingGame.GameGraph(ShannonSwitchingGame.Vertex[ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4)], ShannonSwitchingGame.Edge[ShannonSwitchingGame.Edge(1, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), 3.4333066144268356, :neutral), ShannonSwitchingGame.Edge(2, ShannonSwitchingGame.Vertex(2), ShannonSwitchingGame.Vertex(4), 0.2688945350833061, :neutral), ShannonSwitchingGame.Edge(3, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(3), 7.986814792475403, :neutral), ShannonSwitchingGame.Edge(4, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(4), 3.4193397541577255, :neutral), ShannonSwitchingGame.Edge(5, ShannonSwitchingGame.Vertex(3), ShannonSwitchingGame.Vertex(2), 8.130144968949729, :neutral)], ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(4))
```
"""
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
        graph = random_graph(n, m)
        if isnothing(graph)
            println("Fehler")
            return nothing
        end
        for edge in graph.edges
            edge.weight = rand(Float64)*10
        end
        return graph
    end
                  
end

function _check_st_connection(graph::GameGraph)::Bool
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

using Test

@testset "new_game" begin
    g = random_graph(6, 7)
    @test g !== nothing

    state = new_game(g)

    @test state.graph === g
    @test state.short_Graph.s == g.s
    @test state.short_Graph.t == g.t
    @test isempty(state.short_Graph.edges)
    @test isempty(state.A)
    @test isempty(state.B)
    @test state.current_player == :short
    @test state.winner === nothing
    @test isempty(state.history)
end


@testset "valid_moves" begin
    g = random_graph(6, 7)
    state = new_game(g)

    @test length(valid_moves(state)) == length(g.edges)

    e = first(g.edges)
    e.state = :short

    moves = valid_moves(state)
    @test e ∉ moves
    @test length(moves) == length(g.edges) - 1
end


@testset "make_move! - short player" begin
    g = random_graph(6, 7)
    state = new_game(g)

    e = first(valid_moves(state))

    make_move!(state, e)

    @test e.state == :short
    @test e in state.short_Graph.edges
    @test state.current_player == :cut
    @test length(state.history) == 1
    @test state.history[1] == (:short, e)
end


@testset "make_move! - cut player" begin
    g = random_graph(6, 7)
    state = new_game(g)

    e1 = first(valid_moves(state))
    make_move!(state, e1)

    e2 = first(valid_moves(state))
    n_before = length(state.graph.edges)

    make_move!(state, e2)

    @test e2.state == :cut
    @test length(state.graph.edges) == 7 - 1
    @test state.current_player == :short
    @test length(state.history) == 2
    @test state.history[2] == (:cut, e2)
end


@testset "make_move! mit ungültigem Zug" begin
    g = random_graph(6, 7)
    state = new_game(g)

    e = first(valid_moves(state))
    e.state = :cut

    hist = copy(state.history)

    make_move!(state, e)

    @test state.history == hist
end


@testset "check_winner" begin
    # Kein Gewinner zu Beginn
    g = random_graph(6, 7)
    state = new_game(g)

    @test check_winner(state) === nothing
end


@testset "random_graph - gültiger Graph" begin
    n = 8
    m = 10

    g = random_graph(n, m)

    @test g !== nothing
    @test length(g.vertices) == n
    @test length(g.edges) == m
    @test g.s == g.vertices[1]
    @test g.t == g.vertices[end]

    @test all(e.state == :neutral for e in g.edges)
end


@testset "random_graph - weighted" begin
    g = random_graph(8, 10, weighted=true)

    @test g !== nothing
    @test all(0.0 <= e.weight <= 10.0 for e in g.edges)
end


@testset "random_graph - ungültige Parameter" begin
    @test random_graph(3,5) === nothing
    @test random_graph(6,5) === nothing
    @test random_graph(6,20) === nothing
end

