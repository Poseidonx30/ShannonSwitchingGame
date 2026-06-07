using Gtk4
using Cairo

# Globale Referenz für den aktuell geladenen Graphen
current_graph = Ref{Union{Nothing, GameGraph}}(nothing)

# Hauptfenster erstellen
win = GtkWindow("Shannon-Switching-Game", 1024, 768)
Gtk4.maximize(win)

# Layouts aufbauen
vbox = GtkBox(:v)
vbox.spacing = 10
vbox.margin_top = 10
vbox.margin_bottom = 10
vbox.margin_start = 10
vbox.margin_end = 10

hbox_inputs = GtkBox(:h)
hbox_inputs.spacing = 10

# Inputs & Buttons
entry_n = GtkEntry()
entry_n.placeholder_text = "Anzahl Knoten (n)"
entry_n.hexpand = true

entry_m = GtkEntry()
entry_m.placeholder_text = "Anzahl Kanten (m)"
entry_m.hexpand = true

btn_new_game = GtkButton("Start New Game")

push!(hbox_inputs, entry_n)
push!(hbox_inputs, entry_m)
push!(hbox_inputs, btn_new_game)

# NEU: Ein Label für Status- und Fehlermeldungen (wird unter den Inputs platziert)
status_label = GtkLabel("")
# Optional: Text linksbündig ausrichten
status_label.halign = Gtk4.Align_START 

# Canvas (Zeichenfläche)
canvas = GtkCanvas()
canvas.vexpand = true  
canvas.hexpand = true

# Layout zusammensetzen
push!(vbox, hbox_inputs)
push!(vbox, status_label) # Das Label sitzt jetzt elegant zwischen Inputs und Canvas
push!(vbox, canvas)
win.child = vbox

# --- HILFSFUNKTION FÜR TEMPORÄRE MELDUNGEN (KORRIGIERT) ---
function show_message!(msg::String)
    status_label.label = msg  # .label statt .text verwendet
    
    @async begin
        sleep(4.0) 
        # Nur löschen, wenn in der Zwischenzeit keine neue Meldung kam
        if status_label.label == msg
            status_label.label = ""
        end
    end
end

# --- ZEICHEN-LOGIK (Cairo) ---
@guarded draw(canvas) do widget
    ctx = getgc(canvas)
    w = width(canvas)
    h = height(canvas)

    # Hintergrund weiß
    set_source_rgb(ctx, 1.0, 1.0, 1.0)
    paint(ctx)

    # Abbrechen, wenn noch kein Graph existiert
    current_graph[] === nothing && return

    graph = current_graph[]
    num_vertices = length(graph.vertices)
    num_vertices == 0 && return

    # Kreis-Parameter berechnen
    center_x = w / 2
    center_y = h / 2
    radius = min(w, h) * 0.4 

    # 1. Positionen der Knoten im Kreis berechnen
    node_positions = Dict{Int, Tuple{Float64, Float64}}()
    for (i, v) in enumerate(graph.vertices)
        angle = (i - 1) * (2 * pi / num_vertices)
        x = center_x + radius * cos(angle)
        y = center_y + radius * sin(angle)
        node_positions[v.id] = (x, y)
    end

    # 2. Kanten zeichnen
    set_line_width(ctx, 2.0)
    for edge in graph.edges
        u_id = edge.u.id
        v_id = edge.v.id

        if haskey(node_positions, u_id) && haskey(node_positions, v_id)
            x1, y1 = node_positions[u_id]
            x2, y2 = node_positions[v_id]
            
            if edge.state == :neutral
                set_source_rgb(ctx, 0.4, 0.4, 0.4)
            elseif edge.state == :short
                set_source_rgb(ctx, 0.0, 0.8, 0.0)
                set_line_width(ctx, 4.0)
            elseif edge.state == :cut
                set_source_rgb(ctx, 0.8, 0.0, 0.0)
            end

            if u_id == v_id
                arc(ctx, x1 + 15, y1 - 15, 15.0, 0, 2*pi)
                stroke(ctx)
            else
                move_to(ctx, x1, y1)
                line_to(ctx, x2, y2)
                stroke(ctx)
            end
            set_line_width(ctx, 2.0)
        end
    end

    # 3. Knoten zeichnen
    node_radius = 20.0
    for v in graph.vertices
        x, y = node_positions[v.id]

        if v.id == graph.s.id
            set_source_rgb(ctx, 0.2, 0.8, 0.2)
        elseif v.id == graph.t.id
            set_source_rgb(ctx, 0.8, 0.2, 0.2)
        else
            set_source_rgb(ctx, 0.2, 0.5, 0.8)
        end

        arc(ctx, x, y, node_radius, 0, 2*pi)
        fill(ctx)
        set_source_rgb(ctx, 0.0, 0.0, 0.0)
        arc(ctx, x, y, node_radius, 0, 2*pi)
        stroke(ctx)

        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        set_font_size(ctx, 14.0)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
        
        text_str = string(v.id)
        extents = zeros(Float64, 6)
        ccall((:cairo_text_extents, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Float64}), ctx.ptr, text_str, extents)
        
        text_x = x - extents[3] / 2
        text_y = y + extents[4] / 2
        
        move_to(ctx, text_x, text_y)
        show_text(ctx, text_str)
    end
end

# --- EVENT HANDLER ---
signal_connect(btn_new_game, "clicked") do _
    n_val = tryparse(Int, Gtk4.text(entry_n))
    m_val = tryparse(Int, Gtk4.text(entry_m))

    # 1. Check: Überhaupt Zahlen eingegeben?
    if isnothing(n_val) || isnothing(m_val)
        show_message!("Bitte gültige Zahlen für n und m eingeben!")
        return
    end

    # 2. Check: Die "Langweilig"-Kriterien aus deiner random_graph Funktion spiegeln
    if m_val < n_val || n_val <= 3 || m_val >= n_val*(n_val-1)/2 || m_val >= 2*n_val
        show_message!("Langweilig! Wähle ≥ n Kanten, ≥ 4 Knoten und nicht zu viele Kanten.")
        return
    end

    # Wenn alles passt, Graph generieren
    new_g = random_graph(n_val, m_val)
    
    if isnothing(new_g)
        show_message!("Fehler beim Erstellen des Graphen.")
        return
    end

    current_graph[] = new_g
    show_message!("Graph erfolgreich generiert!")

    # Canvas neu zeichnen
    Gtk4.draw(canvas)
end

show(win)

# ==============================================================================
# KORRIGIERTE ERWEITERUNG: SPIELSTEUERUNG & INTERAKTION (Ganz unten anhängen)
# ==============================================================================

# Globale Referenz für den Zustand des aktuellen Spiels
current_game_state = Ref{Union{Nothing, GameState}}(nothing)

# Funktion zur sauberen Aktualisierung des Status-Labels (ohne Emojis)
function update_game_status!()
    if current_game_state[] === nothing
        status_label.label = "Kein aktives Spiel. Bitte n und m eingeben und starten."
    else
        state = current_game_state[]
        if state.winner !== nothing
            status_label.label = "=== SPIEL BEENDET! GEWINNER: $(uppercase(string(state.winner))) ==="
        else
            status_label.label = "Aktueller Zug: Spieler [ $(uppercase(string(state.current_player))) ] -- Klicke auf eine freie Kante!"
        end
    end
end

# Mathematische Hilfsfunktion: Kürzester Abstand eines Klicks (px, py) zu einer Kante
function distance_to_edge(px, py, x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0.0 && dy == 0.0
        return hypot(px - x1, py - y1)
    end
    t = ((px - x1) * dx + (py - y1) * dy) / (dx^2 + dy^2)
    t = clamp(t, 0.0, 1.0)
    return hypot(px - (x1 + t * dx), py - (y1 + t * dy))
end

# Wir nutzen das native @guarded draw-Makro von Gtk4.jl, um das Zeichnen zu erweitern
@guarded draw(canvas) do widget
    ctx = getgc(canvas)
    w = width(canvas)
    h = height(canvas)

    # Hintergrund weiß zeichnen
    set_source_rgb(ctx, 1.0, 1.0, 1.0)
    paint(ctx)

    current_graph[] === nothing && return
    graph = current_graph[]
    num_vertices = length(graph.vertices)
    num_vertices == 0 && return

    # Koordinaten der Knoten im Kreis berechnen
    center_x = w / 2
    center_y = h / 2
    radius = min(w, h) * 0.4 

    node_positions = Dict{Int, Tuple{Float64, Float64}}()
    for (i, v) in enumerate(graph.vertices)
        angle = (i - 1) * (2 * pi / num_vertices)
        node_positions[v.id] = (center_x + radius * cos(angle), center_y + radius * sin(angle))
    end

    # 1. GESTRICHELTE CUT-KANTEN AUS DER HISTORY ZEICHNEN
    # Da deine make_move! Funktion zerstörte Kanten aus graph.edges löscht,
    # holen wir uns diese Kanten hier exklusiv aus der Historie des GameStates.
    if current_game_state[] !== nothing
        set_line_width(ctx, 2.0)
        set_source_rgb(ctx, 0.8, 0.0, 0.0)  # Rot für Cut
        Cairo.set_dash(ctx, [6.0, 4.0], 0.0) # Gestrichelt-Muster: 6px Linie, 4px Lücke
        
        for (player, edge) in current_game_state[].history
            if player == :cut
                if haskey(node_positions, edge.u.id) && haskey(node_positions, edge.v.id)
                    x1, y1 = node_positions[edge.u.id]
                    x2, y2 = node_positions[edge.v.id]
                    move_to(ctx, x1, y1)
                    line_to(ctx, x2, y2)
                    stroke(ctx)
                end
            end
        end
        Cairo.set_dash(ctx, Float64[], 0.0) # Linienstil wieder zurücksetzen
    end

    # 2. NEUTRALE UND FETTE SHORT-KANTEN ZEICHNEN
    for edge in graph.edges
        u_id = edge.u.id
        v_id = edge.v.id

        if haskey(node_positions, u_id) && haskey(node_positions, v_id)
            x1, y1 = node_positions[u_id]
            x2, y2 = node_positions[v_id]
            
            if edge.state == :neutral
                set_source_rgb(ctx, 0.4, 0.4, 0.4)
                set_line_width(ctx, 2.0)
            elseif edge.state == :short
                set_source_rgb(ctx, 0.0, 0.8, 0.0) # Grün für Short
                set_line_width(ctx, 6.0)           # FEET markiert!
            end

            if u_id == v_id
                arc(ctx, x1 + 15, y1 - 15, 15.0, 0, 2*pi)
                stroke(ctx)
            else
                move_to(ctx, x1, y1)
                line_to(ctx, x2, y2)
                stroke(ctx)
            end
            set_line_width(ctx, 2.0)
        end
    end

    # 3. KNOTEN ZEICHNEN
    node_radius = 20.0
    for v in graph.vertices
        x, y = node_positions[v.id]

        if v.id == graph.s.id
            set_source_rgb(ctx, 0.2, 0.8, 0.2)
        elseif v.id == graph.t.id
            set_source_rgb(ctx, 0.8, 0.2, 0.2)
        else
            set_source_rgb(ctx, 0.2, 0.5, 0.8)
        end

        arc(ctx, x, y, node_radius, 0, 2*pi)
        fill(ctx)
        set_source_rgb(ctx, 0.0, 0.0, 0.0)
        set_line_width(ctx, 2.0)
        arc(ctx, x, y, node_radius, 0, 2*pi)
        stroke(ctx)

        # Verwende deine funktionierende ccall-Methode für Text-Extents
        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        set_font_size(ctx, 14.0)
        select_font_face(ctx, "Arial", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
        
        text_str = string(v.id)
        extents = zeros(Float64, 6)
        ccall((:cairo_text_extents, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Float64}), ctx.ptr, text_str, extents)
        
        text_x = x - extents[3] / 2
        text_y = y + extents[4] / 2
        
        move_to(ctx, text_x, text_y)
        show_text(ctx, text_str)
    end
end

# MOUSE-CLICK LOGIK: Über Gtk4-Event-Controller registrieren
gesture = GtkGestureClick()
push!(canvas, gesture)

function on_canvas_pressed(controller, n_press, x, y)
    state = current_game_state[]
    (state === nothing || state.winner !== nothing) && return

    w = width(canvas)
    h = height(canvas)
    graph = state.graph
    num_vertices = length(graph.vertices)
    num_vertices == 0 && return
    
    node_positions = Dict{Int, Tuple{Float64, Float64}}()
    for (i, v) in enumerate(graph.vertices)
        angle = (i - 1) * (2 * pi / num_vertices)
        node_positions[v.id] = (w/2 + (min(w, h)*0.4)*cos(angle), h/2 + (min(w, h)*0.4)*sin(angle))
    end

    clicked_edge = nothing
    closest_distance = 15.0 # Klicktoleranz in Pixeln

    for edge in graph.edges
        edge.state != :neutral && continue 
        
        if haskey(node_positions, edge.u.id) && haskey(node_positions, edge.v.id)
            x1, y1 = node_positions[edge.u.id]
            x2, y2 = node_positions[edge.v.id]
            
            d = distance_to_edge(x, y, x1, y1, x2, y2)
            if d < closest_distance
                closest_distance = d
                clicked_edge = edge
            end
        end
    end

    if clicked_edge !== nothing
        make_move!(state, clicked_edge)
        update_game_status!()
        draw(canvas) # Aktualisiert das Bild nativ
    end
end

signal_connect(on_canvas_pressed, gesture, "pressed")

# Button-Klick erweitern, um parallel auch das Spiel-Objekt (GameState) zu initialisieren
signal_connect(btn_new_game, "clicked") do _
    sleep(0.05) # Wartet kurz, bis dein originaler Button-Handler den Graphen erzeugt hat
    if current_graph[] !== nothing
        current_game_state[] = new_game(current_graph[])
        update_game_status!()
        draw(canvas)
    end
end

# Start-Status setzen
update_game_status!()