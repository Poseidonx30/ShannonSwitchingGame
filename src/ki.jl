function FC(Sehne::Edge, Spannbaum::GameGraph)
    println("hallo")
    adj = Dict{Any, Vector{Edge}}()
    for edge in Spannbaum.edges
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end

    cumulated_Edges = [Sehne] #aktuell besuchter Weg 
    S = Base.Set([Sehne.u])  #Besuchte Knoten
    Q = [Sehne.u]  #Stack
    while !isempty(Q) && Q[end] !== Sehne.v
        u = Q[end]
        found_edge = false
        for edge in adj[u] 
            nachbar = (edge.u === u) ? edge.v : edge.u
            if nachbar ∉ S
                push!(S, nachbar)
                push!(Q, nachbar)
                push!(cumulated_Edges, edge)
                found_edge = true
                filter!(e -> e !== edge, adj[nachbar])
                filter!(e -> e !== edge, adj[u])
                break
            end 
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

#= using Base

Base.:(==)(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

function gemeinsame_Sehnen(G::GameGraph, T1::GameGraph, T2::GameGraph)::Set(Edge)
    EdgesG = Set(G.edges)
    EdgesT1 = Set(T1.edges)
    EdgesT2 = Set(T2.edges)
    return setdiff(EdgesG, union(EdgesT1, EdgesT2))
end

function Augment(T1::GameGraph, T2::GameGraph, e::Edge)::Bool
    parent = Dict{Edge, Edge}()
    L = FC(e, T1)
    Lp = Set{Edge}()
    while !issetequal(L, Lp)
        Lp = L
        if k % 2 == 0
            T = T1
        else
            T = T2
        end
        TEdges = Set(T.edges)
        if !isempty(intersect(L,TEdges))
            f = rand(collect(intersect(L,TEdges)))
            x = f
            chain = Vector{Edge}(f)
            while x ∈ parent
                x = par[x]
                # chain = 
            end
        else

        end
    end
    return true
end =#