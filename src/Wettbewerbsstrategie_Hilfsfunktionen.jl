const punishment = 160.0

struct ComponentTracker
    parent::Vector{Int}
    size::Vector{Int}
    base_parent::Vector{Int} # Snapshot-Speicher
    base_size::Vector{Int}   # Snapshot-Speicher
    id_to_idx::Dict{Int, Int}
    idx_to_id::Vector{Int}

    ComponentTracker(p, s, bp, bs, id2idx, idx2id) = new(p, s, bp, bs, id2idx, idx2id)

    function ComponentTracker(vertex_ids::Vector{Int})
        n = length(vertex_ids)
        parent = collect(1:n)
        size = fill(1, n)
        
        # Die Snapshot-Arrays werden einmalig mit der gleichen Größe angelegt
        base_parent = collect(1:n)
        base_size = fill(1, n)
        
        id_to_idx = Dict{Int, Int}()
        sizehint!(id_to_idx, n)
        idx_to_id = Vector{Int}(undef, n)
    
        for (idx, id) in enumerate(vertex_ids)
            id_to_idx[id] = idx
            idx_to_id[idx] = id
        end
    
        return new(parent, size, base_parent, base_size, id_to_idx, idx_to_id)
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
    short_graph::GameGraph
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

Base.copy(ct::ComponentTracker)::ComponentTracker = ComponentTracker(copy(ct.parent), copy(ct.size), copy(ct.base_parent), copy(ct.base_size), copy(ct.id_to_idx), copy(ct.idx_to_id))

Base.copy(g::GameGraph)::GameGraph = GameGraph(copy(g.vertices), copy(g.edges), g.s, g.t)

Base.copy(g::EfficientGameGraph)::EfficientGameGraph = EfficientGameGraph(copy(g.edges), copy(g.components), g.s, g.t)

function d_copy(g::GameGraph)::GameGraph
    new_vertices = Vector{Vertex}()
    for vertex in g.vertices
        push!(new_vertices, Vertex(vertex.id))
    end
    new_edges = Vector{Edge}()
    for edge in g.edges
        push!(new_edges, Edge(edge.id, new_vertices[findfirst(x->x.id == edge.u.id, new_vertices)], new_vertices[findfirst(x->x.id == edge.v.id, new_vertices)], edge.weight, edge.state))
    end
    return GameGraph(new_vertices, new_edges, g.s, g.t)
end

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

function save_base_state!(ct::ComponentTracker)
    # Speichert den aktuellen Zustand blitzschnell und ohne Allocations
    copyto!(ct.base_parent, ct.parent)
    copyto!(ct.base_size, ct.size)
end

function restore_base_state!(ct::ComponentTracker)
    # Überschreibt die aktuellen Arrays wieder mit dem gespeicherten Zustand
    copyto!(ct.parent, ct.base_parent)
    copyto!(ct.size, ct.base_size)
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
    n = length(Sehnen)
    while i < n && !isdisjoint(T1_edges, T2_edges)   #length(Sehnen) = j + 2 
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
                union!(new_set, fc)
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
    if e1 ∈ T2_edges || e2 ∈ T1_edges 
        g.has_winning_strategy = :cut
        #println(:cut)
    elseif e1 ∈ T1_edges 
        g.has_winning_strategy = g.current_player
        #println(g.current_player)
    else
        g.has_winning_strategy = :short
        #println(:short)
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
            push!(g.imaginary_moves, last_move)
        end
        T1_has_move = (last_move ∈ g.A)
        T2_has_move = !T1_has_move
    end 
    T = T1_has_move ? g.A : g.B
    T_strich = T2_has_move ? g.A : g.B
    if state.current_player == :cut 
        fc_last = FC(last_move, T_strich, g.merged_graph.components)
        next_move = nothing 
        for move in valid_moves(state)
            if move ∈ fc_last && last_move ∈ FC(move, T, g.merged_graph.components)
                next_move = move 
                break  
            end
        end
        if next_move === nothing 
            error("das sollte nicht passieren")
            #return rand(valid_moves(state)) 
        end
    else 
        fc_last = FC(last_move, T_strich, g.merged_graph.components)
        next_moves = Base.Set{Edge}()
        for move in valid_moves(state)
            if move ∈ fc_last && last_move ∈ FC(move, T, g.merged_graph.components) 
                push!(next_moves, move) 
            end
        end
        if isempty(next_moves) #das darf eigentlich nicht passieren
            error("das sollte nicht passieren")
            #return rand(valid_moves(state)) 
        end
        next_move = first(next_moves)
        for e in next_moves
            if e.weight < next_move.weight
                next_move = e
            end
        end
    end 
    T = (state.current_player == :cut) ? T_strich : T
    cut_move = (state.current_player == :cut) ? next_move : last_move
    short_move = (state.current_player == :cut) ? last_move : next_move
    delete!(T, cut_move)
    push!(T, short_move)
    return next_move
end


mutable struct MinHeap
    elements::Vector{Tuple{Int,Float64}}
    size::Int
    position::Vector{Int} 
end

function min_heapify!(A::MinHeap, i::Int)
    while true
        l = 2 * i
        r = 2 * i + 1
        smallest = i
        if l ≤ A.size && A.elements[l][2] < A.elements[smallest][2]
            smallest = l
        end
        if r ≤ A.size && A.elements[r][2] < A.elements[smallest][2]
            smallest = r
        end
        smallest == i && break
        
        A.elements[i], A.elements[smallest] = A.elements[smallest], A.elements[i]
        A.position[A.elements[i][1]] = i
        A.position[A.elements[smallest][1]] = smallest
        i = smallest
    end
    return A
end

function extract_min!(A::MinHeap)
    A.size == 0 && error("Heap ist leer")   
    min_elem = A.elements[1]    
    
    A.elements[1] = A.elements[A.size]
    A.position[A.elements[1][1]] = 1    
    A.size -= 1   
    A.position[min_elem[1]] = 0    
    
    if A.size > 0
        min_heapify!(A, 1)
    end    
    return min_elem
end

function decrease_key!(A::MinHeap, i::Int, k::Float64)
    A.elements[i][2] < k && error("Neuer Wert ist größer als aktueller Wert")    
    A.elements[i] = (A.elements[i][1], k)   
    while i > 1
        parent = i ÷ 2
        if A.elements[parent][2] > A.elements[i][2]
            A.elements[i], A.elements[parent] = A.elements[parent], A.elements[i]
            A.position[A.elements[i][1]] = i
            A.position[A.elements[parent][1]] = parent            
            i = parent
        else
            break
        end
    end
end

function build_heap!(A::MinHeap, elems::AbstractVector{Tuple{Int,Float64}})
    A.size = length(elems)
    for i in 1:A.size
        id, weight = elems[i]
        A.elements[i] = (id, weight)
        A.position[id] = i
    end
    for i in (A.size ÷ 2):-1:1
        min_heapify!(A, i)
    end
end

struct DijkstraWorkspace
    adj::Vector{Vector{Tuple{Int, Float64}}}
    dist::Vector{Float64}
    elems::Vector{Tuple{Int, Float64}}
    heap::MinHeap
end

function DijkstraWorkspace(max_nodes::Int = 50)
    adj = [Tuple{Int, Float64}[] for _ in 1:max_nodes]
    dist = fill(Inf, max_nodes)
    elems = Vector{Tuple{Int, Float64}}(undef, max_nodes)
    
    # Heap-Speicher direkt auf max_nodes festlegen
    heap_elements = fill((0, 0.0), max_nodes)
    heap_position = fill(0, max_nodes)
    heap = MinHeap(heap_elements, 0, heap_position)
    
    return DijkstraWorkspace(adj, dist, elems, heap)
end


function dijkstra(g::GameGraph, s::Vertex, t::Vertex, ws::DijkstraWorkspace)::Float64
    max_id = isempty(g.vertices) ? 0 : maximum(v -> v.id, g.vertices)
    
    if max_id == 0
        return punishment
    end

    if max_id > length(ws.dist)
        error("DijkstraWorkspace zu klein! Erhöhe max_nodes bei der Initialisierung.")
    end

    for i in 1:max_id
        empty!(ws.adj[i])
    end
    fill!(ws.dist, Inf)
    
    for e in g.edges
        push!(ws.adj[e.u.id], (e.v.id, e.weight))
        push!(ws.adj[e.v.id], (e.u.id, e.weight)) 
    end
    
    ws.dist[s.id] = 0.0

    num_vertices = length(g.vertices)
    for (i, vertex) in enumerate(g.vertices)
        ws.elems[i] = (vertex.id, ws.dist[vertex.id])
    end
    
    build_heap!(ws.heap, view(ws.elems, 1:num_vertices)) 
    
    while ws.heap.size > 0
        u_id, u_dist = extract_min!(ws.heap)
        
        if u_dist == Inf 
            break 
        end
        if u_id == t.id
            return u_dist
        end        
        
        for (v_id, weight) in ws.adj[u_id]
            new_dist = u_dist + weight           
            if new_dist < ws.dist[v_id]
                ws.dist[v_id] = new_dist                
                pos = ws.heap.position[v_id]
                if pos > 0 
                    decrease_key!(ws.heap, pos, new_dist)
                end
            end
        end
    end
    
    return punishment
end

using BenchmarkTools
#####################################################################TEST FÜR MINHEAP###############################################
#= println("Generiere Testdaten...")
N = 10_000  # Anzahl der Elemente im Heap
test_elements = [(i, rand()) for i in 1:N]
heap = MinHeap(Tuple{Int,Float64}[], 0, zeros(Int, N)) #für optimierte Version
println("\n--- Benchmark: insert! ---")
@btime begin
    h = MinHeap(Tuple{Int,Float64}[], 0, Int[])
    insert!(h, $test_elements)
end
insert!(heap, test_elements)
println("\n--- Benchmark: decrease_key! ---")
target_id = 5000
position_in_heap = heap.position[target_id]
@btime decrease_key!($heap, $position_in_heap, 0.0)
println("\n--- Benchmark: extract_min! ---")
@btime begin
    # deepcopy ist nötig, da Dicts und Vektoren kopiert werden müssen
    h_copy = deepcopy($heap) 
    extract_min!(h_copy)
end =#
##########################################################################TEST FÜR DIJKSTRA##################################################
#= n = 1000
m = 1500
println("Generiere Zufallsgraphen mit $n Knoten und $m Kanten...")
g = random_graph(n, m, weighted = true)
println("Benchmark startet. Das kann einen Moment dauern...")
# 3. Dijkstra benchmarken
@btime dijkstra($g, $g.s, $g.t) =#

#########################################################################BENCHMARK SPIELE###########################################################
const OUTFILE = "benchmark_neu_1.3.txt"
const ERRORFILE = "errors_neu_1.3.txt"

# Dateien initialisieren (Errorlog leeren)
open(ERRORFILE, "w") do io
    println(io, "Fehlerlog gestartet\n")
end

function test()
    computer_wins = 0
    random_wins = 0

    computer_points_sum = 0.0
    random_points_sum = 0.0

    total_computer_moves = 0
    computer_move_time_sum = 0.0
    global_max_computer_time = 0.0

    i = 1
    while i ≤ 2 # Limit nach Bedarf anpassen

        n = rand(6:25)
        m = rand(floor(Int, 1.5*n):min(2n - 1))

        g = random_graph(n, m, weighted = true)

        ####################################################
        # Random vs Computer (weighted_cut)
        ####################################################

        game = new_game(d_copy(g))
        len = length(valid_moves(game))

        while len ≥ 1
            make_move!(game, rand(valid_moves(game)))
            len -= 1

            if len ≥ 1
                try
                    t1 = time_ns()
                    make_move!(game, weighted_cut(game))
                    t2 = time_ns()

                    dt = (t2 - t1) / 1e6
                    dt ≥ 2000 && println("cut", n, m)
                    total_computer_moves += 1
                    computer_move_time_sum += dt
                    if dt > global_max_computer_time
                        global_max_computer_time = dt
                    end
                catch e
                    open(ERRORFILE, "a") do io
                        println(io, "ERROR in weighted_cut (Spiel $i)")
                        println(io, "n=$n, m=$m")
                        for (exc, bt) in current_exceptions()
                            showerror(io, exc, bt)
                            println(io)
                        end
                        println(io, "\n")
                    end 
                end

                len -= 1
            end
        end

        points_random = dijkstra(
            game.short_Graph,
            game.short_Graph.s,
            game.short_Graph.t,
            DijkstraWorkspace(50)
        )
        
        ####################################################
        # Computer vs Random (weighted_short)
        ####################################################

        game = new_game(d_copy(g))
        len = length(valid_moves(game))
        
        while len ≥ 1
            try
                t1 = time_ns()
                make_move!(game, weighted_short(game))
                t2 = time_ns()

                dt = (t2 - t1) / 1e6
                dt ≥ 2000 && println("short", n, m)
                total_computer_moves += 1
                computer_move_time_sum += dt
                if dt > global_max_computer_time
                    global_max_computer_time = dt
                end
            catch e
                open(ERRORFILE, "a") do io
                    println(io, "ERROR in weighted_short (Spiel $i)")
                    println(io, "n=$n, m=$m")
                    for (exc, bt) in current_exceptions()
                        showerror(io, exc, bt)
                        println(io)
                    end
                    println(io, "\n")
                end 
            end

            len -= 1

            if len ≥ 1
                make_move!(game, rand(valid_moves(game)))
                len -= 1
            end
        end

        points_computer = dijkstra(
            game.short_Graph,
            game.short_Graph.s,
            game.short_Graph.t, DijkstraWorkspace(50)
        )

        ####################################################
        # Statistik & Gewinner ermitteln
        ####################################################

        if points_computer < points_random
            computer_wins += 1
        else
            random_wins += 1
        end

        computer_points_sum += points_computer
        random_points_sum += points_random

        win_percentage_computer = (computer_wins / i) * 100
        mean_points_computer = computer_points_sum / i
        mean_points_random = random_points_sum / i
        mean_computer_time = total_computer_moves > 0 ? (computer_move_time_sum / total_computer_moves) : 0.0

        ####################################################
        # Benchmark Output (Überschreibt die Datei jedes Mal)
        ####################################################

        open(OUTFILE, "w") do io
            println(io, "========================================")
            println(io, "Spiele bis jetzt gespielt: $i")
            println(io, "Computer-Siegesquote:      $(round(win_percentage_computer, digits=2)) %")
            println(io, "Mittlere Punktzahl (Comp): $(round(mean_points_computer, digits=2))")
            println(io, "Mittlere Punktzahl (Rand): $(round(mean_points_random, digits=2))")
            println(io, "Mittlere Computerzugzeit:  $(round(mean_computer_time, digits=2)) ms")
            println(io, "Maximale Computerzugzeit:  $(round(global_max_computer_time, digits=2)) ms")
            println(io, "========================================")
        end
        i += 1
    end
end