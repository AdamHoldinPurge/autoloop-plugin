#!/bin/bash
# SuperTask™ — Creative Direction Presets
#
# Source this file, then call: get_preset_description "Preset Name"
# Returns a detailed creative direction paragraph for prompt injection.

get_preset_description() {
    local preset="$1"
    case "$preset" in
        "Faithful")
            echo "CREATIVE DIRECTION: FAITHFUL TO PROMPT
Execute the mission exactly as described. Do not take creative liberties, do not add flourishes or stylistic interpretations beyond what was explicitly requested. If the prompt says blue, use blue — not teal, not navy, not cerulean. Prioritise clarity, correctness, and literal interpretation over artistic expression. Your job is to be a precise craftsman, not an artist. Every decision should trace directly back to something the user asked for. When the prompt is ambiguous, choose the most conventional and expected interpretation."
            ;;
        "Hyper-Creative")
            echo "CREATIVE DIRECTION: HYPER-CREATIVE
Break every convention. You are not building something safe — you are building something nobody has seen before. Use unexpected color combinations (electric lime on deep purple, coral on charcoal). Mix typography styles boldly — pair a heavy slab serif headline with a delicate thin sans-serif body. Create layouts that surprise: asymmetric grids, overlapping elements, text that bleeds off edges, sections at unusual angles. Animations should be theatrical — elements that morph, split, reassemble. Every design decision should make someone say 'I've never seen that before.' Take risks. If it feels safe, push further. The goal is to be memorable, not comfortable."
            ;;
        "Ultra-Modern Minimalist")
            echo "CREATIVE DIRECTION: ULTRA-MODERN MINIMALIST
Less is everything. Channel Swiss International Style and Scandinavian design. Use a maximum of 2 colors plus black and white — prefer monochrome with a single accent color. Typography should be clean sans-serif (Inter, Helvetica Neue, or similar), with extreme size contrast between headings and body. Embrace vast whitespace — let elements breathe with generous padding and margins. Layouts should be grid-perfect with mathematical precision. Remove every element that is not absolutely essential. No gradients, no shadows, no decorative elements. Animations should be subtle and purposeful — gentle fades, smooth slides, nothing bouncy or attention-seeking. The design should feel expensive through restraint."
            ;;
        "Bold & Maximalist")
            echo "CREATIVE DIRECTION: BOLD & MAXIMALIST
More is more. Fill the canvas. Use rich, saturated colors in bold combinations — deep reds, bright yellows, electric blues. Layer elements: background patterns, foreground cards, floating decorative shapes, overlapping sections. Typography should be loud — extra-bold weights, large sizes, mixed styles. Every section should feel dense with content and visual interest. Use gradients, textures, patterns, and decorative borders. Animations should be energetic — elements that scale up, rotate in, bounce, and demand attention. Scrolling should feel like a journey through a richly illustrated book. Think magazine editorial, concert poster, or street art — every pixel working hard."
            ;;
        "Dark & Premium")
            echo "CREATIVE DIRECTION: DARK & PREMIUM
Build for the night. The background is deep black (#0a0a0a) or near-black charcoal. Text is off-white or light grey. Accent colors are muted and luxurious — champagne gold (#c9a96e), silver (#a8a8a8), rose gold (#b76e79), or deep burgundy. Typography should be elegant — thin weights, generous letter-spacing, serif or refined sans-serif fonts. Use subtle glow effects, soft shadows that suggest depth, and gentle gradient overlays. Animations should be smooth and cinematic — slow fades, parallax scrolling, elements that reveal gracefully. The overall feel should be high-end luxury brand, exclusive members club, or premium product launch. Every detail whispers quality."
            ;;
        "Playful & Energetic")
            echo "CREATIVE DIRECTION: PLAYFUL & ENERGETIC
This should feel like opening a birthday present. Use bright, joyful colors — vibrant pink (#ff6b9d), sunshine yellow (#ffd93d), electric blue (#4ecdc4), lime green (#a8e6cf). Corners should be rounded (16px+), shapes should be soft and organic. Typography should be friendly — rounded sans-serifs, playful display fonts for headlines, generous line-height. Add micro-interactions everywhere: buttons that wiggle on hover, icons that bounce, cards that tilt, emojis and illustrative elements sprinkled throughout. Use blob shapes, wavy dividers, confetti particles. Animations should be bouncy with spring physics — overshoot and settle. The overall tone is optimistic, fun, and approachable — like a well-designed app for creative people."
            ;;
        "Retro & Nostalgic")
            echo "CREATIVE DIRECTION: RETRO & NOSTALGIC
Channel the warmth of analog design. Use a color palette of muted earth tones — burnt orange (#c45d3a), mustard yellow (#d4a843), olive green (#6b7c4e), warm brown (#8b6e4e), cream (#f5e6c8). Typography should feature serif fonts (Georgia, Playfair Display) for headlines and classic body fonts. Add subtle paper textures, grain overlays, and vignette effects. Borders should be slightly rough or hand-drawn feeling. Use vintage-inspired decorative elements: simple line art, botanical illustrations, badge/stamp designs. Layouts should reference print design — clear columns, pull quotes, drop caps. Animations should be gentle and analog-feeling — soft transitions, no harsh movements. The feel should be artisan coffee shop, independent bookstore, or vinyl record sleeve."
            ;;
        "Organic & Natural")
            echo "CREATIVE DIRECTION: ORGANIC & NATURAL
Draw from nature in every decision. Colors should be earth-derived — forest green (#2d5f3f), sky blue (#87ceeb), terracotta (#cc6b49), sand (#d4c5a9), stone grey (#8a8580), petal pink (#e8b4b8). Avoid sharp corners — use rounded shapes, irregular curves, and organic blobs. Typography should be warm and natural — humanist sans-serifs or soft serifs with natural proportions. Use nature photography, botanical illustrations, or abstract organic patterns as decorative elements. Layouts should flow like water — not rigidly gridded but gently guided. Spacing should be generous and breathing. Animations should be slow and smooth like growing plants or flowing water. The overall feel should be wellness brand, eco-friendly product, or botanical garden — calm, grounded, and alive."
            ;;
        "Corporate & Professional")
            echo "CREATIVE DIRECTION: CORPORATE & PROFESSIONAL
Build trust through structure. Use a palette of blues (#1a56db, #3b82f6, #dbeafe), greys (#374151, #6b7280, #f3f4f6), and white. Typography should be clean and authoritative — system fonts or professional sans-serifs (Inter, Open Sans, Roboto) at sensible sizes. Layouts must be grid-based with perfect alignment — 12-column grid, consistent gutters, modular sections. Use data visualizations, charts, statistics, and trust indicators (logos, certifications, testimonials). Cards should have subtle shadows and clean borders. Animations should be minimal and professional — simple fades, slide-ins, no playful effects. The overall feel should be enterprise SaaS, consulting firm, or financial institution — competent, reliable, and organized. Every element should signal 'we know what we are doing.'"
            ;;
        "Avant-Garde & Experimental")
            echo "CREATIVE DIRECTION: AVANT-GARDE & EXPERIMENTAL
This is art, not just a website. Challenge every assumption about how a page should look. Use unconventional layouts: elements that overlap deliberately, text that runs vertically or diagonally, sections with no clear boundaries, scroll-driven transformations. Colors should be striking and unexpected — neon on pastel, monochrome with a single violent accent. Typography should be expressive — variable fonts that animate, extreme sizes (200px headlines), mixed languages of form. Break the grid intentionally and visibly. Use generative patterns, glitch effects, noise textures, or mathematical visualizations as backgrounds. Animations should be immersive — cursor-reactive elements, scroll-driven narratives, elements that deconstruct and reconstruct. The feel should be digital art gallery, experimental fashion brand, or architecture portfolio — provocative and unforgettable."
            ;;
        "Brutalist & Raw")
            echo "CREATIVE DIRECTION: BRUTALIST & RAW
Strip away all decoration. Expose the structure. Use monospace fonts (JetBrains Mono, Fira Code, Courier) for everything. Colors should be stark — black and white with optional single accent (red #ff0000, blue #0000ff). Borders should be thick (2-4px solid black). No border-radius, no shadows, no gradients. Elements should feel raw and honest — visible grid lines, exposed structure, content-first. Use system defaults where possible. Links should be underlined, buttons should look like buttons. No hero images, no decorative illustrations. If imagery is needed, use high-contrast black and white. Animations should be abrupt — instant state changes, no easing, no transitions longer than 100ms. The feel should be early web revival, concrete architecture, or punk zine — deliberately anti-polish and proud of it."
            ;;
        "Warm & Inviting")
            echo "CREATIVE DIRECTION: WARM & INVITING
Make people feel at home. Use a warm color palette — soft amber (#f59e0b), warm rose (#e11d48 at 20% opacity), cream (#fef3c7), warm grey (#78716c), gentle coral (#fb923c). Corners should be rounded (12-20px). Typography should be friendly and readable — medium-weight sans-serifs with generous line-height (1.7+), comfortable reading sizes (18px+ body). Use warm photography with natural lighting, illustrations of people, or cozy scenes. Spacing should be generous — nothing should feel cramped or rushed. Cards should have soft shadows and warm tint overlays. Animations should be gentle — slow fades (400ms+), subtle parallax, elements that ease in softly. The overall feel should be welcoming SaaS product, family brand, or neighbourhood business — the user should feel cared for and comfortable from the first moment."
            ;;
        *)
            echo ""
            ;;
    esac
}

# List all available presets (for zenity dropdowns)
list_presets() {
    echo "Faithful"
    echo "Hyper-Creative"
    echo "Ultra-Modern Minimalist"
    echo "Bold & Maximalist"
    echo "Dark & Premium"
    echo "Playful & Energetic"
    echo "Retro & Nostalgic"
    echo "Organic & Natural"
    echo "Corporate & Professional"
    echo "Avant-Garde & Experimental"
    echo "Brutalist & Raw"
    echo "Warm & Inviting"
}

# List non-Faithful presets (for V2/V3 selection)
list_creative_presets() {
    echo "Hyper-Creative"
    echo "Ultra-Modern Minimalist"
    echo "Bold & Maximalist"
    echo "Dark & Premium"
    echo "Playful & Energetic"
    echo "Retro & Nostalgic"
    echo "Organic & Natural"
    echo "Corporate & Professional"
    echo "Avant-Garde & Experimental"
    echo "Brutalist & Raw"
    echo "Warm & Inviting"
}
