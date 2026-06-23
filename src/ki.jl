function search_connecting_edge(u::Vertex, v::Vertex, T1::GameGraph, T2::GameGraph)::Edge
    comp_u_in_T2 = DFS(u, T2.edges)[1]
    comp_v_in_T2 = DFS(v, T2.edges)[1]

    for edge in T1.edges 
        if (edge.u ∈ comp_u_in_T2 && edge.v ∈ comp_v_in_T2) || (edge.v ∈ comp_u_in_T2 && edge.u ∈ comp_v_in_T2)
            return edge 
        end
    end 
end

function FC(Sehne::Edge, Spannbaum::GameGraph)::Base.Set{Edge}
    adj = Dict{Any, Vector{Edge}}()
    for edge in Spannbaum.edges
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end

    cumulated_Edges = [Sehne] #aktuell besuchter Weg 
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

using Base

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

function gemeinsame_Sehnen(G::GameGraph, T1::GameGraph, T2::GameGraph)::Base.Set{Edge}
    EdgesG = Base.Set(G.edges)
    EdgesT1 = Base.Set(T1.edges)
    EdgesT2 = Base.Set(T2.edges)
    return setdiff(EdgesG, Base.union(EdgesT1, EdgesT2))
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

# Chase:
function chase(g::GameState)
    if g.has_winning_strategy == :neutral # wir sind im ersten Zug
        T1 = kruskal(g.graph)
        T2 = kruskal(g.graph)
        Sehnen = collect(gemeinsame_Sehnen(g.graph, T1, T2))
        push!(Sehnen, Edge(-1, g.graph.s, g.graph.t, 0.0, :neutral))
        push!(Sehnen, Edge(-2, g.graph.s, g.graph.t, 0.0, :neutral))
        i = 1
        while i < length(Sehnen) && !isempty(intersect(T1.edges, T2.edges))   #length(Sehnen) = j + 2 
            b = Sehnen[i]
            Layers = Vector{Base.Set{Edge}}()
            push!(Layers, Base.Set([b]))
            parent = Dict{Edge, Edge}()
            k=1
            while k ≤ length(g.graph.vertices)
                T = k%2 == 0 ? T2 : T1
                next_T = k%2 == 0 ? T1 : T2
                new_set = Base.Set{Edge}()
                for elem ∈ Layers[k]
                    fc = setdiff(FC(elem, T), [elem])
                    for elem2 ∈ fc
                        parent[elem2] = elem
                    end
                    new_set = Base.union(new_set, fc)
                end
                push!(Layers, new_set)
                if k ≥ 2 && issetequal(Base.Set([edge.id for edge in Layers[k-1]]), Base.Set([edge.id for edge in Layers[k+1]])) # dann ist der Augmentierungsschritt fehlgeschlagen
                    break
                elseif k ≥ 2
                    S = intersect(setdiff(Layers[k+1], Layers[k-1]), next_T.edges)
                else
                    S = intersect(Layers[k+1], next_T.edges)
                end
                if !isempty(S)
                    bk = collect(S)[1]
                    chain = Vector{Edge}()
                    push!(chain, bk)
                    x = bk
                    while x ∈ keys(parent)
                        pushfirst!(chain, parent[x])
                        x = parent[x]
                    end
                    push!(T1.edges, Sehnen[i])
                    even_chain = [chain[i] for i in eachindex(chain) if i % 2 == 0]
                    uneven_chain = [chain[i] for i in eachindex(chain) if abs(i % 2) == 1]
                    T1.edges = collect(Base.union(T1.edges, even_chain))
                    T2.edges = collect(Base.union(T2.edges, uneven_chain))
                    T1.edges = [edge for edge in T1.edges if edge ∉ uneven_chain]
                    T2.edges = [edge for edge in T2.edges if edge ∉ even_chain]
                    break
                end
                k += 1
            end
            i += 1
        end
        return T1, T2
        #=
        g.A, g.B = MaximallyDistantTrees(G.graph, T1, T2)
        second_imaginary = findfirst(x -> x.id == -2, state.A.edges)
        first_imaginary = findfirst(x -> x.id == -1, state.B.edges)
        if !isnothing(first_imaginary) || !isnothing(second_imaginary)
            g.has_winning_strategy = :cut
        else
            g.has_winning_strategy = :short
        end
        =#
    end
    if g.has_winning_strategy == g.current_player # Computer kann gewinnen
        last_move_id = isempty(g.history) ? -1 : g.history[end][2].id
        if last_move_id ∉ symdiff([edge.id for edge in T1.edges], [edge.id for edge in T2.edges])
            return random(valid_moves(g)) # Invariante bleibt erhalten
        else
            if last_move_id ∈ [edge.id for edge in T1.edges]
                T = T1
                T_alt = T2
            else
                T = T2
                T_alt = T1
            end
            next_move = nothing
            for move in valid_moves(g)
                if move ∈ setdiff(FC(T.edges[findfirst(x -> x.id == -1, T.edges)], T_alt), [T.edges[findfirst(x -> x.id == -1, T.edges)]]) && last_move_id ∈ setdiff([edge.id for edge in setdiff(FC(move,T), [move])])
                    next_move = move
                end
            end
            if g.current_player == :cut
                T_alt.edges = [edge for edge in T_alt.edges if edge.id != next_move.id]
                push!(T_alt.edges, g.history[end][2]) # history ist nichtleer, denn cut ist immer min. zweiter Spieler
            else
                T.edges = [edge for edge in T.edges if edge.id != last_move_id]
                push!(T.edges, next_move)
            end
            return next_move
        end
    else
        return random(valid_moves(g))
    end
end