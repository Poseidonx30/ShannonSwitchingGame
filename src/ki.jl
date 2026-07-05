using Base

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

function _FC(Sehne::Edge, Spannbaum::Base.Set{Edge})::Base.Set{Edge}
    adj = Dict{Any, Vector{Edge}}()
    for edge in Spannbaum
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end

    cumulated_Edges = [] #aktuell besuchter Weg - ohne Sehne
    Q = [Sehne.u]  #Stack
    while !isempty(Q) && Q[end] !== Sehne.v
        u = Q[end]
        found_edge = false
        for edge in get(adj, u, Edge[]) 
            nachbar = (edge.u === u) ? edge.v : edge.u
            push!(Q, nachbar)
            push!(cumulated_Edges, edge)
            found_edge = true
            filter!(e -> e !== edge, adj[nachbar])
            filter!(e -> e !== edge, adj[u])
            break
        end
        if !found_edge   #Sackgasse
            pop!(Q)
            if !isempty(cumulated_Edges)
                pop!(cumulated_Edges) # Die hinführende Kante entfernen
            end
        end
    end   
    return Base.Set(cumulated_Edges)
end

function _gemeinsame_Sehnen(G::GameGraph, T1::Base.Set{Edge}, T2::Base.Set{Edge})::Base.Set{Edge}
    EdgesG = Base.Set(G.edges)
    return setdiff(EdgesG, Base.union(T1, T2))
end

function _kruskal(G::GameGraph)::GameGraph
    edges = Vector{Edge}()
    elements = Dict{Vertex,Element}()
    sets = Dict{Vertex,customSet}()
    for v in G.vertices
        merge!(elements, Dict{Vertex,Element}(v => Element(v, nothing, nothing)))
        merge!(sets, Dict{Vertex,customSet}(v => _make_set(elements[v])))
    end
    for e in G.edges
        if length(sets) == 1
            break
        elseif _find_set(elements[e.u]) !== _find_set(elements[e.v])
            deletedSet = _union(elements[e.u], elements[e.v])
            delete!(sets, deletedSet.value)
            push!(edges, e)
        end
    end
    return GameGraph(G.vertices, edges , G.s, G.t)
end

"""
    who_can_win(g::GameState)::Symbol

Entscheidet, welcher der beiden Spieler im Zustand g gewinnen kann. Derjenige Spieler, der gewinnen kann, wird zurückgegeben und in g.has_winning_strategy gespeichert. Die Gewinnbedingung findet sich in <https://doi.org/10.1145/361284.361293>.

# Beispiel
```julia
julia> g = random_graph(4,5);

julia> state = new_game(g);

julia> state.has_winning_strategy
:neutral

julia> who_can_win(state)
:short

julia> state.has_winning_strategy
:short
```
"""
function who_can_win(g::GameState)::Symbol
    T1 = _kruskal(g.graph)
    T2 = _kruskal(g.graph)
    T1_edges = Base.Set(T1.edges)
    T2_edges = Base.Set(T2.edges)
    Sehnen = collect(_gemeinsame_Sehnen(g.graph, T1_edges, T2_edges))
    e1 = Edge(-1, g.graph.s, g.graph.t, 0.0, :neutral)
    e2 = Edge(-2, g.graph.s, g.graph.t, 0.0, :neutral)
    g.e1 = e1
    push!(Sehnen, e1, e2)
    i = 0
    while i < length(Sehnen) && !isempty(intersect(T1_edges, T2_edges))   #length(Sehnen) = j + 2 
        i += 1
        b = Sehnen[i]
        Layers = Vector{Base.Set{Edge}}()
        push!(Layers, Base.Set([b]))
        parent = Dict{Edge, Edge}()
        k=0
        while true
            k += 1
            T = (k % 2 == 1) ? T1_edges : T2_edges
            T_next = (k % 2 == 1) ? T2_edges : T1_edges
            new_set = Base.Set{Edge}()
            for elem ∈ Layers[k]
                fc = _FC(elem, T)
                for elem2 ∈ fc
                    if !haskey(parent, elem2)
                        parent[elem2] = elem
                    end
                end
                new_set = Base.union(new_set, fc)
            end  
            push!(Layers, new_set)
            if k == 1
                if isempty(Layers[k+1]) 
                    break
                end
                S = intersect(Layers[k+1], T_next)
            else 
                if issetequal(Layers[k+1], Layers[k-1])
                    break
                end  
                S = intersect(setdiff(Layers[k+1], Layers[k-1]), T_next)
            end 
            if isempty(S)
                continue # dann ist der Augmentierungsschritt fehlgeschlagen
            end 
            bk = first(S) #bessere Laufzeit O(1)
            while k > 0
                b_prev = parent[bk]
                delete!(T, bk)   #Hat angeblich amortisierte Laufzeit O(1) - also besser als symmdiff
                push!(T, b_prev)
                bk = b_prev
                k -= 1
                T = (k % 2 == 1) ? T1_edges : T2_edges
            end 
            break 
        end
    end
    g.A = T1_edges
    g.B = T2_edges
    if e1 ∈ T1_edges
        g.has_winning_strategy = :short
    elseif e1 ∈ T2_edges || e2 ∈ T1_edges
        g.has_winning_strategy = :cut
    else 
        g.has_winning_strategy = :short
    end
    return g.has_winning_strategy
end

"""
    chase(g::GameState)::Edge

Wählt für g.current_player die korrekte Reaktion auf den zuletzt vom Gegner gespielten Zug aus (wird chase(state) zu Beginn des Spiels aufgerufen, so simuliert die Funktion einen imaginären vom Gegner gespielten Zug). Hat g.current_player keine Gewinnstrategie, wird ein zufälliger Zug zurückgegeben.

# Beispiel
```julia
julia> g = random_graph(4,5); state = new_game(g); who_can_win(state);

julia> chase(state)
ShannonSwitchingGame.Edge(1, ShannonSwitchingGame.Vertex(1), ShannonSwitchingGame.Vertex(2), 0.0, :neutral)
```
"""
function chase(g::GameState)::Edge
    if g.has_winning_strategy == g.current_player # Computer kann gewinnen
        skip = false
        if isempty(g.history)
            if g.e1 ∈ g.A
                last_move = g.e1
            else 
                last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2]))
                push!(g.imaginary_moves, last_move)
                skip = true
            end   
        else
            last_move = g.history[end][2]
        end 
        T1_has_move = (last_move ∈ g.A)
        T2_has_move = (last_move ∈ g.B)
        if (T1_has_move && T2_has_move) || (!T1_has_move && !T2_has_move) || (last_move ∈ g.imaginary_moves && !skip)
            last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2]))
            push!(g.imaginary_moves, last_move)
            T1_has_move = (last_move ∈ g.A)
            T2_has_move = !T1_has_move
        end 
        T = T1_has_move ? g.A : g.B
        T_strich = T2_has_move ? g.A : g.B
        next_move = nothing
        for move in intersect(Base.Set(valid_moves(g)), _FC(last_move, T_strich))
            if last_move ∈ _FC(move, T) 
                next_move = move 
                break
            end
        end
        if next_move === nothing
            println("das sollte nicht passieren")
            return rand(valid_moves(g))
        end
        T = (g.current_player == :cut) ? T_strich : T
        cut_move = (g.current_player == :cut) ? next_move : last_move
        short_move = (g.current_player == :cut) ? last_move : next_move
        delete!(T, cut_move)
        push!(T, short_move)
        return next_move
    else
        return rand(valid_moves(g))
    end
end

using Test

@testset "Shannon Switching Game KI Tests" begin

    v1 = Vertex(1)
    v2 = Vertex(2)
    v3 = Vertex(3)
    v4 = Vertex(4)
    vertices = [v1, v2, v3, v4]
    
    e1 = Edge(1, v1, v2, 0.0, :neutral)
    e2 = Edge(2, v2, v4, 0.0, :neutral)
    e3 = Edge(3, v1, v3, 0.0, :neutral)
    e4 = Edge(4, v3, v4, 0.0, :neutral)
    e5 = Edge(5, v2, v3, 0.0, :neutral)
    edges = [e1, e2, e3, e4, e5]
    
    # Graph G mit s=1 und t=4
    G = GameGraph(vertices, edges, v1, v4)

    # ---------------------------------------------------------
    @testset "Test: _kruskal" begin
        K = _kruskal(G)
        
        # Ein Spannbaum für einen zusammenhängenden Graphen mit 4 Knoten muss exakt 3 Kanten haben
        @test length(K.edges) == 3
        
        # Die Knotenmenge des Spannbaums muss identisch mit der des Originalgraphen sein
        @test Base.Set(K.vertices) == Base.Set(G.vertices)
        
        # Start- und Zielknoten sollten ebenfalls übernommen worden sein
        @test K.s == G.s
        @test K.t == G.t
    end

    # ---------------------------------------------------------
    @testset "Test: _gemeinsame_Sehnen" begin
        # Wir erzeugen einen künstlichen Spannbaum T aus {e1, e2, e3}
        T_edges = Base.Set([e1, e2, e3])
        
        # Wenn T1 und T2 identisch sind, sind die gemeinsamen Sehnen genau die verbleibenden Kanten in G
        sehnen = _gemeinsame_Sehnen(G, T_edges, T_edges)
        
        @test length(sehnen) == 2
        @test e4 ∈ sehnen
        @test e5 ∈ sehnen
        @test isempty(intersect(sehnen, T_edges))
        @test Base.union(sehnen, T_edges) == Base.Set(G.edges)
    end

    # ---------------------------------------------------------
    @testset "Test: _FC (Fundamentalkreis)" begin
        # Definierter Spannbaum T = {e1, e2, e3}
        T = Base.Set([e1, e2, e3]) 
        
        # Fall 1: Sehne e5 (verbindet v2 und v3)
        # Der Pfad in T zwischen v2 und v3 führt über v1 (Kanten e1 und e3)
        fc5 = _FC(e5, T)
        @test length(fc5) == 2
        @test e1 ∈ fc5
        @test e3 ∈ fc5
        
        # Fall 2: Sehne e4 (verbindet v3 und v4)
        # Der Pfad in T zwischen v3 und v4 führt über v1 und v2 (Kanten e3, e1, e2)
        fc4 = _FC(e4, T)
        @test length(fc4) == 3
        @test e1 ∈ fc4
        @test e2 ∈ fc4
        @test e3 ∈ fc4
    end

    # ---------------------------------------------------------
    @testset "Test: who_can_win" begin
        game = new_game(G)
        
        # In G kann :short gewinnen
        winner = who_can_win(game)
        @test winner == :short
        
        # Stelle sicher, dass die Funktion den Wert auch im Struct speichert
        @test game.has_winning_strategy == :short
        
        # Prüfe, ob die Basen A und B korrekt befüllt wurden
        @test !isempty(game.A)
        @test !isempty(game.B)
    end
end