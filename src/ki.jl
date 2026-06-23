function short_strategy(state::GameState)#::Edge #A,B immer nach jedem Zug aktualisiert im state
    if isempty(state.A.edges) && isempty(state.B.edges)      
        push!(state.graph.edges, Edge(0, state.graph.s, state.graph.t, 0.0, :neutral)  )
        T1 = kruskal(state.graph)
        T2 = d_copy(T1)
        state.A, state.B = MaximallyDistantTrees(state.graph, T1, T2)
        pop!(state.graph.edges)
    end 
    if isempty(state.A.edges) && isempty(state.B.edges)  #Falls es keine Gewinnstrategie gibt
        println("Es gibt keine Strategie")
        return rand(valid_moves(state))
    end 
    println("Es gibt Strategie")
    if isempty(state.history)
        removed_edge = Edge(0, state.graph.s, state.graph.t, 0.0, :neutral)  
    else
        removed_edge = state.history[end][2]
    end
    idx_A = findfirst(x -> isequal(x, removed_edge), state.A.edges)
    idx_B = findfirst(x -> isequal(x, removed_edge), state.B.edges)
    if idx_A !== nothing
        deleteat!(state.A.edges, idx_A)
        edge = search_connecting_edge(removed_edge.u, removed_edge.v, state.B, state.A)
        if edge.state != :neutral
            return rand(valid_moves(state))
        else 
            push!(state.A.edges, edge)
            return edge
        end 
    elseif idx_B !== nothing
        deleteat!(state.B.edges, idx_B)
        edge = search_connecting_edge(removed_edge.u, removed_edge.v, state.A, state.B)
        if edge.state != :neutral
            return rand(valid_moves(state))
        else 
            push!(state.B.edges, edge)
            return edge
        end 
    else 
        return rand(valid_moves(state))   
    end
end 

function search_connecting_edge(u::Vertex, v::Vertex, T1::GameGraph, T2::GameGraph)::Edge
    comp_u_in_T2 = DFS(u, T2.edges)[1]
    comp_v_in_T2 = DFS(v, T2.edges)[1]

    for edge in T1.edges 
        if (edge.u ∈ comp_u_in_T2 && edge.v ∈ comp_v_in_T2) || (edge.v ∈ comp_u_in_T2 && edge.u ∈ comp_v_in_T2)
            return edge 
        end
    end 
end

function DFS(start::Vertex, E::Vector{Edge})::Tuple{Base.Set{Vertex}, Base.Set{Edge}} #Darf nur mit Bäumen verwendet werden!!! (sost werden Knoten mehrfach besucht)
    adj = Dict{Any, Vector{Edge}}() #Inzidenzliste  
    for edge in E
        push!(get!(() -> Edge[], adj, edge.u), edge)
        push!(get!(() -> Edge[], adj, edge.v), edge)
    end
    Vertices = Base.Set{Vertex}([start])
    Edges = Base.Set{Edge}()
    Q = [start]

    while !isempty(Q)
        v = Q[end]
        found_edge = false
        for edge in get(adj, v, Edge[])
            found_edge = true
            nachbar = (edge.u === v) ? edge.v : edge.u
            push!(Q, nachbar)
            push!(Vertices, nachbar)
            push!(Edges, edge)
            filter!(e -> e !== edge, adj[nachbar])
            filter!(e -> e !== edge, adj[v])
            break
        end 
        if !found_edge   #Sackgasse
            pop!(Q)
        end
    end 
    return Vertices, Edges
end

function cut_strategy(state::GameState)::Edge #A_cut,B_cut immer nach jedem Zug aktualisiert im state
   #=  if isempty(state.A_cut.edges) && isempty(state.B_cut.edges)
        A_cut = ...
        B_cut = ...
    end =#
    isempty(state.A_cut.edges) && isempty(state.B_cut.edges) && return rand(valid_moves(state)) #Falls es keine Gewinnstrategie gibt
    A_t = Base.Set(A_cut.edges)
    B_t = Base.Set(B_cut.edges)
    Valid = Base.Set(valid_moves(state))
    a = state.history[end][2]
    if a ∈ A_t
        # P = find_path(state.A_cut.edges, state.graph)  
        P = DFS(state.graph.s, state.graph.t, union(union(intersect(state.A_cut.edges, state.short_Graph), state.B_cut.edges), [a]))
        if !isempty(P)
            b = rand(collect(Valid ∩ B_t ∩ P))
        else 
            b = rand(collect(Valid ∩ B_t))
        end 
    elseif a ∈ B_t
        # P = find_path(B_cut.edges, state.graph)
        P = DFS(state.graph.s, state.graph.t, union(union(intersect(state.B_cut.edges, state.short_Graph), state.A_cut.edges), [a]))
        if !isempty(P)
            b = rand(collect(Valid ∩ A_t ∩ P))
        else 
            b = rand(collect(Valid ∩ A_t))
        end 
    else 
        return rand(collect(A_t ∪ B_t))
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
        for edge in get(adj, u, Edge[])
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

#= function Augment(T1::GameGraph, T2::GameGraph, e::Edge)::Bool
    parent = Dict{Edge, Edge}()
    L = FC(e, T1)
    Lp = Base.Set{Edge}()
    k = 1
    while !issetequal(L, Lp)
        Lp = L
        if k % 2 == 1
            T = T1
        else
            T = T2
        end
        TEdges = Base.Set(T.edges)
        if !isempty(intersect(L,TEdges))
            f = rand(collect(intersect(L,TEdges)))
            x = f
            chain = [f]
            while x ∈ keys(parent)
                x = parent[x]
                chain = pushfirst!(chain, x)
            end
            push!(T1.edges, e)
            evenChain = [chain[i] for i in eachindex(chain) if i % 2 == 0]
            unevenChain = [chain[i] for i in eachindex(chain) if i % 2 != 0]
            append!(T1.edges, [evenChain[i] for i in eachindex(evenChain)])
            T1.edges = [edge for edge in T1.edges if edge ∉ unevenChain]
            append!(T2.edges, [unevenChain[i] for i in eachindex(unevenChain)])
            T2.edges = [edge for edge in T2.edges if edge ∉ evenChain]
            return true
        end
        for edge in L
            for edge2 in setdiff(FC(edge,T), L)
                push!(L, edge2)
                parent[edge2] = edge
            end
        end
        k += 1  
    end
    return false
end =#  
function Augment(T1::GameGraph, T2::GameGraph, e::Edge)::Bool
    # Schnelle Lookups für die Bäume erstellen
    T1_set = Base.Set(T1.edges)
    T2_set = Base.Set(T2.edges)
    
    # Die Queue speichert Paare: (aktuelle_kante, herkunft_aus_baum)
    # Herkunft: 0 = Start-Sehne, 1 = Kante gehört zu T1, 2 = Kante gehört zu T2
    queue = [(e, 0)]
    
    parent = Dict{Edge, Edge}()
    visited = Base.Set{Edge}([e])
    
    found_terminal = false
    terminal_edge = nothing
    
    while !isempty(queue)
        curr, indicator = popfirst!(queue)
        
        # FALL A: Wir sind am Start (0) oder kommen aus T2 (2) -> Wir suchen Kreis in T1
        if indicator == 0 || indicator == 2
            circuit = FC(curr, T1)
            for next_edge in circuit
                next_edge === curr && continue # Die Akkord-Kante selbst überspringen
                
                if next_edge ∉ visited
                    push!(visited, next_edge)
                    parent[next_edge] = curr
                    
                    # Da next_edge in T1 liegt: Wenn sie AUCH in T2 ist, 
                    # haben wir eine gemeinsame Kante (Ziel) gefunden!
                    if next_edge ∈ T2_set
                        found_terminal = true
                        terminal_edge = next_edge
                        break
                    end
                    push!(queue, (next_edge, 1))
                end
            end
            
        # FALL B: Wir kommen aus T1 (1) -> Wir suchen Kreis in T2
        else 
            circuit = FC(curr, T2)
            for next_edge in circuit
                next_edge === curr && continue # Die Akkord-Kante selbst überspringen
                
                if next_edge ∉ visited
                    push!(visited, next_edge)
                    parent[next_edge] = curr
                    
                    # Da next_edge in T2 liegt: Wenn sie AUCH in T1 ist -> Treffer!
                    if next_edge ∈ T1_set
                        found_terminal = true
                        terminal_edge = next_edge
                        break
                    end
                    push!(queue, (next_edge, 2))
                end
            end
        end
        
        found_terminal && break
    end
    
    # Wenn ein vergrößernder Pfad gefunden wurde, wenden wir die Schalthistorie an
    if found_terminal
        # Pfad von hinten nach vorne rekonstruieren [e, e1, e2, ..., terminal_edge]
        path = Edge[]
        curr = terminal_edge
        while curr !== e
            pushfirst!(path, curr)
            curr = parent[curr]
        end
        pushfirst!(path, e)
        
        # Kanten entlang des Pfades präzise austauschen (Sicher gegen Multigraphen)
        for i in 1:(length(path)-1)
            u = path[i]
            v = path[i+1]
            if i % 2 != 0
                # Ungerader Schritt: u kommt in T1, v fliegt präzise aus T1
                push!(T1.edges, u)
                idx = findfirst(x -> x === v, T1.edges)
                if idx !== nothing
                    deleteat!(T1.edges, idx)
                end
            else
                # Gerader Schritt: u kommt in T2, v fliegt präzise aus T2
                push!(T2.edges, u)
                idx = findfirst(x -> x === v, T2.edges)
                if idx !== nothing
                    deleteat!(T2.edges, idx)
                end
            end
        end
        return true
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

function MaximallyDistantTrees(G::GameGraph, T1::GameGraph, T2::GameGraph)
    changed = true
    while changed 
        common_edges = gemeinsame_Sehnen(G, T1, T2)
        changed = false
        for sehne in common_edges
            if Augment(T1, T2, sehne)
                changed = true
                break
            end
        end
    end 
    new_vertices_T2 = Vector{Vertex}()
    new_edges_T2 = Vector{Edge}()
    for vertex in T2.vertices
        idx = findfirst(x -> x.id == vertex.id, G.vertices)
        push!(new_vertices_T2, G.vertices[idx])
    end 
    for edge in T2.edges
        idx = findfirst(x -> isequal(x, edge), G.edges)
        push!(new_edges_T2, G.edges[idx])
    end 
    T2.vertices, T2.edges = new_vertices_T2, new_edges_T2
    common_neutral = intersect(filter(e -> e.state == :neutral, T1.edges), filter(e -> e.state == :neutral, T2.edges))
    setdiff!(T1.edges, common_neutral)
    setdiff!(T2.edges, common_neutral)
    v1, e1 = DFS(G.s, T1.edges)
    if G.t ∉ v1
        T1.edges, T1.vertices, T2.edges, T2.vertices = [], [], [], []
    else
        v2, e2 = DFS(G.s, T2.edges)
        if G.t ∉ v2 #kann man sich sparen denke ich
            T1.edges, T1.vertices, T2.edges, T2.vertices = [], [], [], []
        else
            T1.vertices = collect(v1)
            T1.edges = collect(e1)
            T2.vertices = collect(v2) 
            T2.edges = collect(e2)
        end 
    end 
    return T1, T2
end

function d_copy(G::GameGraph)
    return GameGraph(copy(G.vertices), copy(G.edges), G.s, G.t)
end

# Chase:
function chase(g::GameState)
    if g.has_winning_strategy == :neutral # wir sind im ersten Zug
        T1 = kruskal(g.graph)
        T2 = d_copy(T1)
        Sehnen = collect(gemeinsame_Sehnen(g.graph, T1, T2))
        push!(Sehnen, Edge(-1, g.graph.s, g.graph.t, 0.0, :neutral))
        push!(Sehnen, Edge(-2, g.graph.s, g.graph.t, 0.0, :neutral))
        i = 1
        while i ≤ length(Sehnen) && !isempty(intersect(T1.edges, T2.edges))
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
                    # println(elem.id, " ", [elem.id for elem in FC(elem, T)], " ", k)
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
                    for x ∈ keys(parent)
                        pushfirst!(chain, parent[x])
                        x = parent[x]
                    end
                    push!(T1.edges, Sehnen[i])
                    even_chain = [chain[i] for i in eachindex(chain) if i % 2 == 0]
                    uneven_chain = [chain[i] for i in eachindex(chain) if i % 2 == 1]
                    println(even_chain)
                    println(uneven_chain)
                    append!(T1.edges, even_chain)
                    append!(T2.edges, uneven_chain)
                    T1.edges = [edge for edge in T1.edges if edge ∉ uneven_chain]
                    T2.edges = [edge for edge in T2.edges if edge ∉ even_chain]
                    break
                    #=
                    penultimate_layer = collect(Layers[k-1])
                    for i in eachindex(penultimate_layer)
                        if bk ∈ FC(penultimate_layer[i], T) # sollte das nicht T_k-1 sein?
                            if k%2 == 0
                                T2.edges = [edge for edge in T2.edges if ]
                            break
                        end
                    end
                    =#
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
    else
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
end