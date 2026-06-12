function short_strategy(state::GameState)::Edge #A,B immer nach jedem Zug aktualisiert im state
    if isempty(state.A.edges) && isempty(state.B.edges)  #Falls es keine Gewinnstrategie gibt
        return rand(valid_moves(state))
    end 
    if isempty(state.history)
        removed_edge = edge(0, state.graph.s, state.graph.t, 0.0, :neutral) 
    else
        removed_edge = state.history[end][2]
    end
    idx_A = findfirst(A.edges , removed_edge)
    idx_B = findfirst(B.edges , removed_edge)
    if idx_A !== nothing
        # deleteat!(A.edges, idx_A)
        edge = search_connecting_edge(removed_edge.u, removed_edge.v, state.B, state.A)
        if edge.state != :neutral
            return rand(valid_moves(state))
        else 
            return edge
        end 
    elseif idx_B !== nothing
        # deleteat!(B.edges, idx_B)
        edge = search_connecting_edge(removed_edge.u, removed_edge.v, state.B, state.A)
        if edge.state != :neutral
            return rand(valid_moves(state))
        else 
            return edge
        end 
    else 
        return rand(valid_moves(state))   
    end
end 

function search_connecting_edge(u::Vertex, v::Vertex, T1::GameGraph, T2::GameGraph)::Edge
    comp_u_in_T2 = DFS(u, T2.edges)
    comp_v_in_T2 = DFS(v, T2.edges)

    for edge in T1.edges 
        if (edge.u ∈ comp_u_in_T2 && edge.v ∈ comp_v_in_T2) || (edge.v ∈ comp_u_in_T2 && edge.u ∈ comp_v_in_T2)
            return edge 
        end
    end 
end

function DFS(start::Vertex, E::Vector{Edge})::Base.Set{Vertex}
    adj = Dict{Any, Vector{Edge}}() #Inzidenzliste  
    for edge in E
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end
    Vertices = Set{Vertex}([start])
    Q = [start]

    while !isempty(Q)
        v = pop!(Q)
        for edge in adj[v]
            nachbar = (edge.u === v) ? edge.v : edge.u
            push!(Q, nachbar)
            push!(Vertices, nachbar)
            filter!(e -> e !== edge, adj[nachbar])
            filter!(e -> e !== edge, adj[v])
            break
        end 
    end 
    return Vertices
end

function cut_strategy(state::GameState)::Edge #A_cut,B_cut immer nach jedem Zug aktualisiert im state
    if isempty(state.A_cut.edges) && isempty(state.B_cut.edges)  #Falls es keine Gewinnstrategie gibt
        return rand(valid_moves(state))
    end
    A_t = Base.Set(A_cut.edges)
    B_t = Base.Set(B_cut.edges)
    Valid = Base.Set(valid_moves(state))
    a = state.history[end][2]
    if a ∈ A_t
        P = find_path(A_cut.edges, state.graph)  
        if !isempty(P)
            b = rand(Valid ∩ B_t ∩ P)
        else 
            b = rand(Valid ∩ B_t)
        end 
    elseif a ∈ B_t
        P = find_path(B_cut.edges, state.graph)
        if !isempty(P)
            b = rand(Valid ∩ A_t ∩ P)
        else 
            b = rand(Valid ∩ A_t)
        end 
    else 
        return rand(A_t ∪ B_t)
    end 
    return b 
end 

function find_path(S::Vector{Edge}, G::GameGraph)::Base.Set{Edge}
    filter!(e -> e.state == :neutral, S)
    allowed_edges = setdiff(G.edges, S)  #Kanten von G ohne die neutralen Kanten von A bzw. B 
    return DFS(G.s, G.t, allowed_edges)
end

function DFS(s::Vertex, t::Vertex, E::Vector{Edge})::Base.Set{Edge}
    adj = Dict{Any, Vector{Edge}}()
    for edge in E
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end
    cumulated_Edges = [] #aktuell besuchter Weg 
    S = Base.Set([s])  #Besuchte Knoten
    Q = [s]  #Stack
    while !isempty(Q) && Q[end] !== t
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
        for edge in adj[u] 
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

function Augment(T1::GameGraph, T2::GameGraph, e::Edge)::Bool
    parent = Dict{Edge, Edge}()
    L = FC(e, T1)
    Lp = Base.Set{Edge}()
    while !issetequal(L, Lp)
        Lp = L
        if k % 2 == 0
            T = T1
        else
            T = T2
        end
        TEdges = Base.Set(T.edges)
        if !isempty(intersect(L,TEdges))
            f = rand(collect(intersect(L,TEdges)))
            x = f
            chain = Vector{Edge}(f)
            while x ∈ parent
                x = parent[x]
                chain = pushfirst!(chain, x)
            end
            push!(T1.edges, e)
            evenChain = [chain[i] for i in eachindex(chain) if i % 2 == 0]
            unevenChain = [chain[i] for i in eachindex(chain) if i % 2 != 0]
            append!(T1.edges, [chain[i] for i in eachindex(evenChain)])
            T1.edges = [edge for edge in T1.edges if edge ∉ unevenChain]
            appen!(T2.edges, [chain[i] for i in eachindex(unevenChain)])
            T2.edges = [edge for edge in T2.edges if edge ∉ evenChain]
            return true
        end
        for edge in L
            for edge2 in setdiff(FC(edge,T), L)
                L = union(L, edge2)
                parent[edge2] = edge
            end
        end
    end
    return false
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