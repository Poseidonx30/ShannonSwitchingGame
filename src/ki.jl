using Base

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

function FC(Sehne::Edge, Spannbaum::Base.Set{Edge})::Base.Set{Edge}
    adj = Dict{Any, Vector{Edge}}()
    for edge in Spannbaum
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end

    cumulated_Edges = [] #aktuell besuchter Weg - ohne Sehne
    #S = Base.Set([Sehne.u])  #Besuchte Knoten - nicht notwendig, da Spannbaum 
    Q = [Sehne.u]  #Stack
    while !isempty(Q) && Q[end] !== Sehne.v
        u = Q[end]
        found_edge = false
        for edge in get(adj, u, Edge[]) 
            nachbar = (edge.u === u) ? edge.v : edge.u
            #if nachbar ∉ S
                #push!(S, nachbar)
                push!(Q, nachbar)
                push!(cumulated_Edges, edge)
                found_edge = true
                filter!(e -> e !== edge, adj[nachbar])
                filter!(e -> e !== edge, adj[u])
                break
            #end 
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

function gemeinsame_Sehnen(G::GameGraph, T1::Base.Set{Edge}, T2::Base.Set{Edge})::Base.Set{Edge}
    EdgesG = Base.Set(G.edges)
    return setdiff(EdgesG, Base.union(T1, T2))
end

function kruskal(G::GameGraph)::GameGraph
    edges = Vector{Edge}()
    elements = Dict{Vertex,Element}()
    sets = Dict{Vertex,customSet}()
    for v in G.vertices
        merge!(elements, Dict{Vertex,Element}(v => Element(v, nothing, nothing)))
        merge!(sets, Dict{Vertex,customSet}(v => make_set(elements[v])))
    end
    for e in G.edges
        if length(sets) == 1
            break
        elseif find_set(elements[e.u]) !== find_set(elements[e.v])
            deletedSet = union(elements[e.u], elements[e.v])
            delete!(sets, deletedSet.value)
            push!(edges, e)
        end
    end
    return GameGraph(G.vertices, edges , G.s, G.t)
end

function who_can_win(g::GameState)
    T1 = kruskal(g.graph)
    T2 = kruskal(g.graph)
    T1_edges = Base.Set(T1.edges)
    T2_edges = Base.Set(T2.edges)
    Sehnen = collect(gemeinsame_Sehnen(g.graph, T1_edges, T2_edges))
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
                fc = FC(elem, T)
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
        println("short")
        g.has_winning_strategy = :short
    elseif e1 ∈ T2_edges || e2 ∈ T1_edges
        println("cut")
        g.has_winning_strategy = :cut
    else 
        println("short")
        g.has_winning_strategy = :short
    end
end

function chase(g::GameState)
    if g.has_winning_strategy == g.current_player # Computer kann gewinnen
        if isempty(g.history)
            last_move = g.e1  
        else
            last_move = g.history[end][2]
        end 
        T1_has_move = (last_move ∈ g.A)
        T2_has_move = (last_move ∈ g.B)
        if (T1_has_move && T2_has_move) || (!T1_has_move && !T2_has_move) || last_move ∈ g.imaginary_moves
            last_move = rand(symdiff(g.A, g.B))
            push!(g.imaginary_moves, last_move)
            T1_has_move = (last_move ∈ g.A)
            T2_has_move = !T1_has_move
        end 
        T = T1_has_move ? g.A : g.B
        T_strich = T2_has_move ? g.A : g.B
        next_move = nothing
        for move in intersect(Base.Set(valid_moves(g)), FC(last_move, T_strich))
            if last_move ∈ FC(move, T) 
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