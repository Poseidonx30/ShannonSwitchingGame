#unsere alten Funktionen optimiert und an die neue Datenstruktur für Zusammenhangskomponenten angepasst - in Zusammenarbeit mit Gemini :)
struct ComponentTracker
    parent::Vector{Int}
    size::Vector{Int}
    id_to_idx::Dict{Int, Int}  # Map: Reale ID -> Array-Index
    idx_to_id::Vector{Int}     # Map: Array-Index -> Reale ID (für die Rückgabe)

    ComponentTracker(p, s, id2idx, idx2id) = new(p, s, id2idx, idx2id)

    function ComponentTracker(vertex_ids::Vector{Int})
        n = length(vertex_ids)
        parent = collect(1:n)
        size = fill(1, n)
        id_to_idx = Dict{Int, Int}()
        sizehint!(id_to_idx, n) # Optimiert den Speicher des Dicts vorab
        idx_to_id = Vector{Int}(undef, n)
    
        for (idx, id) in enumerate(vertex_ids)
            id_to_idx[id] = idx
            idx_to_id[idx] = id
        end
    
        return new(parent, size, id_to_idx, idx_to_id)
    end
end

mutable struct EfficientGameGraph
    edges::Base.Set{Edge}  
    components::ComponentTracker      #Short fügt hierin zusammen
    s::Vertex                 
    t::Vertex                 
end

mutable struct ExtendedGameState
    graph::EfficientGameGraph
    merged_graph::EfficientGameGraph
    A::Base.Set{Edge} 
    B::Base.Set{Edge} 
    e1::Edge
    e2::Edge
    has_winning_strategy::Symbol
    current_player::Symbol
    first_optimal_move::Bool 
    imaginary_moves::Base.Set{Edge}
    winner::Union{Symbol, Nothing}
end

Base.copy(ct::ComponentTracker)::ComponentTracker = ComponentTracker(copy(ct.parent), copy(ct.size), copy(ct.id_to_idx), copy(ct.idx_to_id))

function _find_idx!(ct::ComponentTracker, idx::Int)::Int
    if ct.parent[idx] == idx
        return idx
    end
    ct.parent[idx] = _find_idx!(ct, ct.parent[idx]) # Pfadkompression
    return ct.parent[idx]
end

function get_component!(ct::ComponentTracker, id::Int)::Int
    idx = ct.id_to_idx[id] 
    root_idx = _find_idx!(ct, idx)
    return ct.idx_to_id[root_idx]
end

function merge_components!(ct::ComponentTracker, u_id::Int, v_id::Int)
    u_idx = ct.id_to_idx[u_id]
    v_idx = ct.id_to_idx[v_id]
    
    root_u = _find_idx!(ct, u_idx)
    root_v = _find_idx!(ct, v_idx)
    
    if root_u != root_v
        if ct.size[root_u] < ct.size[root_v]
            root_u, root_v = root_v, root_u
        end
        ct.parent[root_v] = root_u
        ct.size[root_u] += ct.size[root_v]
    end
end

function check_st_connection(G::EfficientGameGraph)::Bool
    if get_component!(G.components, G.s.id) == get_component!(G.components, G.t.id)
        return true
    end
    temp_components = copy(G.components)
    for e in G.edges
        merge_components!(temp_components, e.u.id, e.v.id)
        if get_component!(temp_components, G.s.id) == get_component!(temp_components, G.t.id)
            return true
        end
    end    
    return false
end

function kruskal(G::EfficientGameGraph, minimal::Bool)::Base.Set{Edge}
    temp_components = copy(G.components)
    tree_edges = Base.Set{Edge}()  
    if minimal
        edges_to_process = sort(collect(G.edges), by = e -> e.weight)
    else
        edges_to_process = G.edges
    end 
    for e in edges_to_process
        root_u = get_component!(temp_components, e.u.id)
        root_v = get_component!(temp_components, e.v.id)
        if root_u != root_v
            push!(tree_edges, e) 
            merge_components!(temp_components, e.u.id, e.v.id)
        end
    end   
    return tree_edges
end

function gemeinsame_Sehnen(G::EfficientGameGraph, T1::Base.Set{Edge})::Base.Set{Edge}
    EdgesG = Base.Set{Edge}()
    for e in G.edges
        if (get_component!(G.components, e.u.id) != get_component!(G.components, e.v.id)) && e ∉ T1
            push!(EdgesG, e)
        end 
    end      
    return EdgesG
end

function FC(Sehne::Edge, Spannbaum::Base.Set{Edge}, components::ComponentTracker)::Base.Set{Edge} 
    start_root = get_component!(components, Sehne.u.id)
    target_root = get_component!(components, Sehne.v.id)
    
    adj = Dict{Int, Vector{Tuple{Int, Edge}}}() #Adjazenzliste der Form Key: Root-ID der Komponente -> Value: Liste von (Nachbar-Root-ID, Kante im Spannbaum)
    
    for e in Spannbaum # Diese Kante verbindet zwei verschiedene Komponenten, Wir fügen sie als Kante hinzu
        root_u = get_component!(components, e.u.id)
        root_v = get_component!(components, e.v.id)
        push!(get!(adj, root_u, Tuple{Int, Edge}[]), (root_v, e))  #bitte frag mich nichts zu get ;)
        push!(get!(adj, root_v, Tuple{Int, Edge}[]), (root_u, e))
    end

    # Pfadsuche mittels DFS  -  meine Version war wohl nicht sehr effizient 
    parent_map = Dict{Int, Tuple{Int, Edge}}() # Wir speichern: parent_node[node] = (predecessor_node, edge_that_connected_them)
    visited = Set{Int}([start_root])
    stack = [start_root]
    
    found = false
    while !isempty(stack)
        curr_root = pop!(stack)  

        if curr_root == target_root
            found = true
            break
        end
        
        for (neighbor_root, edge) in get(adj, curr_root, Tuple{Int, Edge}[])
            if neighbor_root ∉ visited
                push!(visited, neighbor_root)
                parent_map[neighbor_root] = (curr_root, edge)
                push!(stack, neighbor_root)
            end
        end
    end
    
    cycle = Base.Set{Edge}()
    if found
        # Rückverfolgung vom Ziel zum Start
        curr = target_root
        while curr != start_root
            prev_node, edge = parent_map[curr]
            push!(cycle, edge)
            curr = prev_node
        end
    end
    
    return cycle
end

function who_can_win(g::ExtendedGameState, minimal::Bool)
    T1_edges = kruskal(g.merged_graph, minimal)
    T2_edges = Base.copy(T1_edges)
    if minimal 
        Sehnen = sort(collect(gemeinsame_Sehnen(g.merged_graph, T1_edges)), by = e -> e.weight)
    else 
        Sehnen = collect(gemeinsame_Sehnen(g.merged_graph, T1_edges))
    end 
    e1 = g.e1
    e2 = g.e2  #ich hoffe im Wettbewerb gibt es keine Kanten mit Gewichten -1, -2; sonst ändern
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
                fc = FC(elem, T, g.merged_graph.components)
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
            bk = first(S) 
            while k > 0
                b_prev = parent[bk]
                delete!(T, bk)   
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
    if e1 ∈ T2_edges || e2 ∈ T1_edges || e1 ∈ T1_edges
        println("cut")
        g.has_winning_strategy = :cut
    else 
        println("short")
        g.has_winning_strategy = :short
    end
end

function chase(g::ExtendedGameState, state::GameState)::Edge
    skip = false
    if g.first_optimal_move == true 
        if g.e1 ∈ g.A 
            last_move = g.e1  
        else 
            last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2])) #wie unten
            push!(g.imaginary_moves, last_move)
            skip = true 
        end 
        g.first_optimal_move = false
    else
        last_move = state.history[end][2]
    end 
    T1_has_move = (last_move ∈ g.A)
    T2_has_move = (last_move ∈ g.B)
    if (T1_has_move && T2_has_move) || (!T1_has_move && !T2_has_move) || last_move ∈ g.imaginary_moves || get_component!(g.merged_graph.components, last_move.u.id) == get_component!(g.merged_graph.components, last_move.v.id)
        if !skip 
            last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2]))   #nicht optimal für Short. Man sollte wahrscheinlich einen Zug wählen, auf den die Antwort möglichst günstig ist.
            #Auf alle möglichen zufälligen Züge aus der sym.diff. die Antwort zu berechnen (ggf. zusammen mit MCTS) dauert vlt. aber zu lang
            push!(g.imaginary_moves, last_move)
        end 
        T1_has_move = (last_move ∈ g.A)
        T2_has_move = !T1_has_move
    end 
    T = T1_has_move ? g.A : g.B
    T_strich = T2_has_move ? g.A : g.B
    if state.current_player == :cut 
        next_move = nothing 
        for move in intersect(Base.Set(valid_moves(state)), FC(last_move, T_strich, g.merged_graph.components))
            if last_move ∈ FC(move, T, g.merged_graph.components) 
                next_move = move 
                break  
            end
        end
        if next_move === nothing 
            println("das sollte nicht passieren")
            return rand(valid_moves(state)) #MCTS
        end 
    else 
        next_moves = Base.Set{Edge}()
        for move in intersect(Base.Set(valid_moves(state)), FC(last_move, T_strich, g.merged_graph.components))
            if last_move ∈ FC(move, T, g.merged_graph.components) 
                push!(next_moves, move) 
            end
        end
        if isempty(next_moves) #das darf eigentlich nicht passieren
            println("das sollte nicht passieren")
            return rand(valid_moves(state)) #MCTS 
        end
        next_move = minimum(next_moves, by = e -> e.weight)  #hier vlt. MCTS auf alle Antworten - für Short
    end 
    T = (g.current_player == :cut) ? T_strich : T
    cut_move = (g.current_player == :cut) ? next_move : last_move
    short_move = (g.current_player == :cut) ? last_move : next_move
    delete!(T, cut_move)
    push!(T, short_move)
    return next_move
end

mutable struct MinHeap
    elements::Vector{Tuple{Int,Float64}}
    size::Int
    MinHeap() = new([],0)
end

function min_heapify!(A::MinHeap, i::Int)
    i > A.size && return A
    l = 2*i
    r = 2*i+1
    if l ≤ A.size && A.elements[l][2] < A.elements[i][2]
        smallest = l
    else
        smallest = i
    end
    if r ≤ A.size && A.elements[r][2] < A.elements[i][2]
        smallest = r
    end
    if smallest != i
        if smallest == l
            temp = A.elements[i]
            A.elements[i] = A.elements[l]
            A.elements[l] = temp
        else
            temp = A.elements[i]
            A.elements[i] = A.elements[r]
            A.elements[r] = temp
        end
        return min_heapify!(A, smallest)
    end
    return A
end

function extract_min!(A::MinHeap)
    A.elements[1], A.elements[A.size] = A.elements[A.size], A.elements[1]
    A.size -= 1
    min_heapify!(A,1)
    return A.elements[A.size+1]
end

function decrease_key!(A::MinHeap,i::Int,k::Float64)
    A.elements[i] = (A.elements[i][1],k)
    while i > 1 && A.elements[i ÷ 2][2] > A.elements[i][2]
        A.elements[i], A.elements[i÷2] = A.elements[i÷2], A.elements[i]
        i = i÷2
    end
end

function insert!(A::MinHeap, val::Tuple{Int,Float64})
    A.size += 1
    if length(A.elements) >= A.size
        A.elements[A.size] = (val[1],Inf)
    else
        push!(A.elements, (val[1],Inf))
    end
    decrease_key!(A, A.size, val[2])
end

#=
function dijkstra(g::GameGraph, s::Vertex, t::Vertex)
    old_vertex_ids = [vertex.id for vertex ∈ g.vertices]
    i=1
    for vertex ∈ g.vertices
        vertex.id = i
        i+= 1
    end
    y = Dict{Vertex, Float64}() # speichert die Kosten, um zu einem Knoten zu kommen
    heap = MinHeap()
    for vertex ∈ g.vertices
        if vertex == s
            insert!(heap, (vertex.id, 0))
            y[w] = 0
        else
            insert!(heap, (vertex.id, Inf))
            y[w] = Inf
        end
    end
    while !isempty(heap.elements)
        v = extract_min!(heap)
        for e ∈ g.edges
            if e.u.id == v.id && y[w] > v[2] + e.weight
                decrease_key!(heap,)
=#

