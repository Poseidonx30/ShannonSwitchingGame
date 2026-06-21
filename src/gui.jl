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

# ==============================================================================
# ERWEITERTE SPIELSTEUERUNG & INTERAKTION (INKL. KI-MODUS)
# ==============================================================================

# Globale Referenzen für den Zustand des aktuellen Spiels und den KI-Modus
current_game_state = Ref{Union{Nothing, GameState}}(nothing)
computer_role = Ref{Symbol}(:none) # :none (PvP), :short (Computer fängt an), :cut (Mensch fängt an)

# Neuen Button für den Computer-Modus erstellen und ins Layout packen
btn_vs_computer = GtkButton("Spiele gegen Computer")
push!(hbox_inputs, btn_vs_computer)

# Funktion zur sauberen Aktualisierung des Status-Labels
function update_game_status!()
    if current_game_state[] === nothing
        status_label.label = "Kein aktives Spiel. Bitte n und m eingeben und starten."
    else
        state = current_game_state[]
        if state.winner !== nothing
            status_label.label = "=== SPIEL BEENDET! GEWINNER: $(uppercase(string(state.winner))) ==="
        else
            # Zusatzinfo anzeigen, wer gerade dran ist
            ki_info = ""
            if computer_role[] != :none
                ki_info = (state.current_player == computer_role[]) ? " (Computer überlegt...)" : " (Du bist dran!)"
            end
            status_label.label = "Aktueller Zug: Spieler [ $(uppercase(string(state.current_player))) ]$ki_info -- Klicke auf eine freie Kante!"
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

# --- COMPUTER-ZUG LOGIK ---
function computer_move!()
    state = current_game_state[]
    (state === nothing || state.winner !== nothing) && return
    computer_role[] == :none && return

    # Prüfen, ob wirklich die KI am Zug ist
    if state.current_player == computer_role[]
        # Entsprechende Strategie-Funktion aus deinem Modul aufrufen
        edge = if computer_role[] == :short
            short_strategy(state)
        else
            cut_strategy(state)
        end

        if edge !== nothing
            println(edge)
            make_move!(state, edge)
            update_game_status!()
            Gtk4.draw(canvas)
        end 
    end
end

# --- ZENTRALE INITIALISIERUNG FÜR NEUE SPIELE ---
function init_game!(vs_computer::Bool)
    n_val = tryparse(Int, Gtk4.text(entry_n))
    m_val = tryparse(Int, Gtk4.text(entry_m))

    # 1. Check: Überhaupt Zahlen eingegeben?
    if isnothing(n_val) || isnothing(m_val)
        show_message!("Bitte gültige Zahlen für n und m eingeben!")
        return
    end

    # 2. Check: Validierung der Kriterien
    if m_val < n_val || n_val <= 3 || m_val >= n_val*(n_val-1)/2 || m_val >= 2*n_val
        show_message!("Langweilig! Wähle ≥ n Kanten, ≥ 4 Knoten und nicht zu viele Kanten.")
        return
    end

    # Graph generieren
    new_g = random_graph(n_val, m_val)
    if isnothing(new_g)
        show_message!("Fehler beim Erstellen des Graphen.")
        return
    end

    # Globale Zustände setzen
    current_graph[] = new_g
    current_game_state[] = new_game(new_g)

    if vs_computer
        # Zufällig bestimmen, wer anfängt. Der erste Spieler ist immer :short!
        if rand(Bool)
            computer_role[] = :short   # Computer ist Short -> fängt an
            show_message!("Spiel gegen Computer gestartet! Computer fängt an (:short).")
        else
            computer_role[] = :cut     # Mensch ist Short -> fängt an (Computer ist Cut)
            show_message!("Spiel gegen Computer gestartet! Du fängst an (:short).")
        end
    else
        computer_role[] = :none
        show_message!("Normales 2-Spieler-Spiel erfolgreich generiert!")
    end

    update_game_status!()
    Gtk4.draw(canvas)

    # Falls die KI als :short ausgelost wurde, zieht sie sofort mit einer kleinen Verzögerung
    if vs_computer && computer_role[] == :short
        @async begin
            sleep(0.6)
            computer_move!()
        end
    end
end

# --- BUTTON EVENT HANDLER ---
signal_connect(btn_new_game, "clicked") do _
    init_game!(false) # Lokales PvP-Spiel
end

signal_connect(btn_vs_computer, "clicked") do _
    init_game!(true)  # Spiel gegen den Computer
end

# --- MOUSE-CLICK LOGIK (Überarbeitet für KI-Verhalten) ---
gesture = GtkGestureClick()
push!(canvas, gesture)

function on_canvas_pressed(controller, n_press, x, y)
    state = current_game_state[]
    (state === nothing || state.winner !== nothing) && return

    # Blockiert Klicks, wenn die KI am Zug ist
    if computer_role[] != :none && state.current_player == computer_role[]
        return
    end

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
        # Zug des menschlichen Spielers ausführen
        make_move!(state, clicked_edge)
        update_game_status!()
        Gtk4.draw(canvas)
        
        # Falls das Spiel noch läuft und eine KI aktiv ist, zieht diese im Anschluss automatisch
        if state.winner === nothing && computer_role[] != :none
            @async begin
                sleep(0.5) # Kurze Pause, damit der Zug des Spielers optisch wahrnehmbar ist
                computer_move!()
            end
        end
    end
end

signal_connect(on_canvas_pressed, gesture, "pressed")

# Start-Status beim Laden der GUI setzen
update_game_status!()

show(win)