#!/usr/bin/env python3
"""SuperTask™ — GTK3 Config Dialog
Replaces zenity --forms with a proper reactive dialog.
Outputs pipe-separated config values on stdout for launcher.sh to parse."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, GLib, Pango, Gdk, GdkPixbuf
import os
import sys
import json
import subprocess
import tempfile
import shutil
import threading
from urllib.request import urlopen
from zipfile import ZipFile
from io import BytesIO

ICON_PATH = os.path.expanduser('~/.claude/plugins/autoloop/icon.png')
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ACCOUNTS_FILE = os.path.expanduser('~/.claude/plugins/autoloop/accounts/accounts.json')
CONFIG_BASE = os.path.expanduser('~/.claude-supertask')
DEFAULT_CONFIG = os.path.expanduser('~/.claude')

PRESET_NAMES = [
    'Faithful', 'Hyper-Creative', 'Ultra-Modern Minimalist',
    'Bold & Maximalist', 'Dark & Premium', 'Playful & Energetic',
    'Retro & Nostalgic', 'Organic & Natural', 'Corporate & Professional',
    'Avant-Garde & Experimental', 'Brutalist & Raw', 'Warm & Inviting'
]

PRESET_DESCRIPTIONS = {
    'Faithful': 'Execute exactly as described — no creative liberties',
    'Hyper-Creative': 'Break conventions, unexpected combos, surprise the viewer',
    'Ultra-Modern Minimalist': 'Whitespace, clean lines, Swiss/Scandinavian design',
    'Bold & Maximalist': 'Dense, layered, rich detail — more is more',
    'Dark & Premium': 'Dark mode, luxury feel, muted golds and silvers',
    'Playful & Energetic': 'Bright colors, rounded shapes, bouncy animations',
    'Retro & Nostalgic': 'Vintage aesthetics, textures, serif fonts, warm tones',
    'Organic & Natural': 'Earth tones, soft curves, nature-inspired',
    'Corporate & Professional': 'Clean, trustworthy, blue/grey palette, grid-based',
    'Avant-Garde & Experimental': 'Push boundaries, unconventional layouts, artistic',
    'Brutalist & Raw': 'Raw HTML energy, exposed structure, monospace fonts',
    'Warm & Inviting': 'Comfortable, friendly, warm colors, rounded corners',
}

MAX_CYCLES_OPTIONS = ['Infinite', '1', '2', '3', '5', '10', '25', '50', '100']
MAX_ITERS_OPTIONS = ['Infinite', '1', '3', '5', '8', '10', '15', '20', '30', '50']
MODEL_OPTIONS = ['opus', 'sonnet', 'haiku']
MODE_OPTIONS = ['General', 'Website Builder']
TIME_LIMIT_OPTIONS = [
    'No limit', '30 minutes', '1 hour', '2 hours',
    '4 hours', '8 hours', '12 hours', '24 hours'
]

REQUIRED_PLUGINS = [
    {
        'id': 'ralph-loop@claude-plugins-official',
        'display': 'Ralph Loop',
        'type': 'marketplace',
        'install_cmd': '/plugin install ralph-loop@claude-plugins-official',
    },
    {
        'id': 'superpowers@claude-plugins-official',
        'display': 'Superpowers',
        'type': 'marketplace',
        'install_cmd': '/plugin install superpowers@claude-plugins-official',
    },
    {
        'id': 'playwright@claude-plugins-official',
        'display': 'Playwright',
        'type': 'marketplace',
        'install_cmd': '/plugin install playwright@claude-plugins-official',
    },
    {
        'id': 'frontend-design@claude-plugins-official',
        'display': 'Frontend Design',
        'type': 'marketplace',
        'install_cmd': '/plugin install frontend-design@claude-plugins-official',
    },
    {
        'id': 'typescript-lsp@claude-plugins-official',
        'display': 'TypeScript LSP',
        'type': 'marketplace',
        'install_cmd': '/plugin install typescript-lsp@claude-plugins-official',
    },
    {
        'id': 'hookify@claude-plugins-official',
        'display': 'Hookify',
        'type': 'marketplace',
        'install_cmd': '/plugin install hookify@claude-plugins-official',
    },
    {
        'id': 'autoloop',
        'display': 'AutoLoop',
        'type': 'local',
        'install_cmd': 'curl -sL https://raw.githubusercontent.com/AdamHoldinPurge/autoloop-plugin/master/install.sh | bash',
    },
]


def get_accounts():
    """Get list of logged-in accounts. Returns [(email, plan, config_dir), ...]"""
    accounts = []
    try:
        result = subprocess.run(
            ['claude', 'auth', 'status', '--json'],
            capture_output=True, text=True, timeout=10,
            env={**os.environ, 'CLAUDECODE': '', 'CLAUDE_CONFIG_DIR': DEFAULT_CONFIG}
        )
        data = json.loads(result.stdout)
        if data.get('loggedIn'):
            accounts.append((
                data.get('email', 'unknown'),
                data.get('subscriptionType', ''),
                DEFAULT_CONFIG
            ))
    except Exception:
        pass

    if os.path.exists(ACCOUNTS_FILE):
        try:
            stored = json.load(open(ACCOUNTS_FILE))
            for a in sorted(stored, key=lambda x: x.get('slot', 0)):
                config_dir = a.get('config_dir', '')
                if not config_dir or config_dir == DEFAULT_CONFIG:
                    continue
                try:
                    result = subprocess.run(
                        ['claude', 'auth', 'status', '--json'],
                        capture_output=True, text=True, timeout=10,
                        env={**os.environ, 'CLAUDECODE': '', 'CLAUDE_CONFIG_DIR': config_dir}
                    )
                    data = json.loads(result.stdout)
                    if data.get('loggedIn'):
                        accounts.append((
                            data.get('email', 'unknown'),
                            data.get('subscriptionType', ''),
                            config_dir
                        ))
                except Exception:
                    pass
        except Exception:
            pass
    return accounts


def find_next_slot():
    used = set()
    if os.path.exists(ACCOUNTS_FILE):
        try:
            stored = json.load(open(ACCOUNTS_FILE))
            used = {a.get('slot', 0) for a in stored}
        except Exception:
            pass
    for i in range(1, 20):
        if i not in used:
            return i
    return 99


def save_account(slot, email, plan, config_dir):
    os.makedirs(os.path.dirname(ACCOUNTS_FILE), exist_ok=True)
    accounts = []
    if os.path.exists(ACCOUNTS_FILE):
        try:
            accounts = json.load(open(ACCOUNTS_FILE))
        except Exception:
            pass
    accounts = [a for a in accounts if a.get('slot') != slot]
    accounts.append({
        'slot': slot, 'email': email, 'plan': plan,
        'config_dir': config_dir, 'label': f'Account {slot}'
    })
    accounts.sort(key=lambda a: a.get('slot', 0))
    json.dump(accounts, open(ACCOUNTS_FILE, 'w'), indent=2)


def check_plugins(config_dir=None):
    """Check which required plugins are installed for a given config dir.
    Each CLAUDE_CONFIG_DIR has its own installed_plugins.json (not symlinked),
    so plugins must be installed per-account. settings.json IS symlinked
    but we check it from the config_dir to be safe.
    Returns dict: {plugin_id: bool}"""
    results = {}
    cdir = config_dir or DEFAULT_CONFIG

    # installed_plugins.json is PER config dir (not symlinked)
    installed_file = os.path.join(cdir, 'plugins', 'installed_plugins.json')
    installed_plugins = {}
    try:
        with open(installed_file) as f:
            data = json.load(f)
            installed_plugins = data.get('plugins', {})
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass

    # settings.json enabledPlugins (symlinked in supertask dirs → shared)
    settings_file = os.path.join(cdir, 'settings.json')
    enabled_plugins = {}
    try:
        with open(settings_file) as f:
            data = json.load(f)
            enabled_plugins = data.get('enabledPlugins', {})
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    for plugin in REQUIRED_PLUGINS:
        pid = plugin['id']
        if plugin['type'] == 'local':
            plugin_dir = os.path.join(cdir, 'plugins', 'autoloop')
            plugin_json = os.path.join(
                plugin_dir, '.claude-plugin', 'plugin.json')
            results[pid] = (os.path.isdir(plugin_dir)
                            and os.path.isfile(plugin_json))
        else:
            is_installed = (pid in installed_plugins
                            and len(installed_plugins[pid]) > 0)
            is_enabled = enabled_plugins.get(pid, False)
            results[pid] = is_installed and is_enabled

    return results


# ════════════════════════════════════════════
#  Preset Picker Dialog
# ════════════════════════════════════════════

class PresetPickerDialog(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(
            title='Pick a Creative Direction',
            transient_for=parent, modal=True, flags=0)
        self.set_default_size(460, 420)
        self.set_resizable(False)
        self.add_buttons('Cancel', Gtk.ResponseType.CANCEL)
        self.selected_preset = None

        content = self.get_content_area()
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(12)
        content.set_margin_bottom(8)

        lbl = Gtk.Label()
        lbl.set_markup('<b>Choose a preset or type your own direction</b>')
        lbl.set_xalign(0)
        lbl.set_margin_bottom(10)
        content.pack_start(lbl, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_min_content_height(340)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)

        for name in PRESET_NAMES:
            if name == 'Faithful':
                continue
            row = Gtk.ListBoxRow()
            row.set_margin_top(2)
            row.set_margin_bottom(2)
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            box.set_margin_start(8)
            box.set_margin_end(8)
            box.set_margin_top(6)
            box.set_margin_bottom(6)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            name_lbl = Gtk.Label()
            name_lbl.set_markup(f'<b>{GLib.markup_escape_text(name)}</b>')
            name_lbl.set_xalign(0)
            text_box.pack_start(name_lbl, False, False, 0)

            desc = PRESET_DESCRIPTIONS.get(name, '')
            desc_lbl = Gtk.Label(label=desc)
            desc_lbl.set_xalign(0)
            desc_lbl.get_style_context().add_class('dim-label')
            desc_lbl.set_line_wrap(True)
            desc_lbl.set_max_width_chars(50)
            text_box.pack_start(desc_lbl, False, False, 0)

            box.pack_start(text_box, True, True, 0)

            btn = Gtk.Button(label='Select')
            btn.connect('clicked', self._on_select, name)
            btn.set_valign(Gtk.Align.CENTER)
            box.pack_start(btn, False, False, 0)

            row.add(box)
            listbox.add(row)

        sw.add(listbox)
        content.pack_start(sw, True, True, 0)
        self.show_all()

    def _on_select(self, _btn, preset_name):
        self.selected_preset = preset_name
        self.response(Gtk.ResponseType.OK)


# ════════════════════════════════════════════
#  Website Builder Brief Dialog
# ════════════════════════════════════════════

class WebsiteBuilderDialog(Gtk.Dialog):
    """Rich form for website builder brief: brand DNA, inspirations, master prompt."""

    def __init__(self, parent, initial_master_prompt='', existing_data=None):
        super().__init__(
            title='Website Builder Brief',
            transient_for=parent, modal=True, flags=0)
        self.set_default_size(620, 700)
        self.set_resizable(True)

        if os.path.exists(ICON_PATH):
            self.set_icon_from_file(ICON_PATH)

        self.add_buttons('Cancel', Gtk.ResponseType.CANCEL,
                         'Save Brief', Gtk.ResponseType.OK)
        ok_btn = self.get_widget_for_response(Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class('suggested-action')

        action_area = self.get_action_area()
        action_area.set_margin_top(8)
        action_area.set_margin_bottom(8)
        action_area.set_margin_start(16)
        action_area.set_margin_end(16)

        # Storage for dynamic lists
        self.brand_url_entries = []
        self.brand_logos = []
        self.brand_reference_images = []
        self.inspo_url_entries = []
        self.inspo_images = []

        content = self.get_content_area()

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content.pack_start(sw, True, True, 0)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        main_box.set_margin_start(16)
        main_box.set_margin_end(16)
        main_box.set_margin_top(12)
        main_box.set_margin_bottom(12)
        sw.add(main_box)

        self._build_brand_dna_section(main_box)
        self._build_inspirations_section(main_box)
        self._build_master_prompt_section(main_box, initial_master_prompt)

        if existing_data:
            self._populate_from_data(existing_data)

        self.show_all()

    # ── Reusable builders ──

    def _make_text_area(self, parent, placeholder='', height=80):
        """Create a multi-line text entry."""
        frame = Gtk.Frame()
        frame.set_shadow_type(Gtk.ShadowType.IN)
        s = Gtk.ScrolledWindow()
        s.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        s.set_min_content_height(height)
        tv = Gtk.TextView()
        tv.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        tv.set_left_margin(6)
        tv.set_right_margin(6)
        tv.set_top_margin(4)
        tv.set_bottom_margin(4)
        s.add(tv)
        frame.add(s)
        parent.pack_start(frame, False, False, 0)
        return tv

    def _add_field_heading(self, parent, title, hint=''):
        """Add a bold field title with optional dim hint below."""
        lbl = Gtk.Label()
        lbl.set_markup(f'<b>{title}</b>')
        lbl.set_xalign(0)
        parent.pack_start(lbl, False, False, 0)
        if hint:
            h = Gtk.Label()
            h.set_markup(f'<small>{hint}</small>')
            h.set_xalign(0)
            h.set_line_wrap(True)
            h.get_style_context().add_class('dim-label')
            parent.pack_start(h, False, False, 0)

    def _make_section_frame(self, parent, title):
        """Create a bordered section frame with title and return inner box."""
        frame = Gtk.Frame()
        frame_lbl = Gtk.Label()
        frame_lbl.set_markup(f'  <b>{title}</b>  ')
        frame.set_label_widget(frame_lbl)
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        inner.set_margin_start(14)
        inner.set_margin_end(14)
        inner.set_margin_top(10)
        inner.set_margin_bottom(14)
        frame.add(inner)
        parent.pack_start(frame, False, False, 0)
        return inner

    def _build_url_list(self, parent, label_text, hint_text, storage_list):
        """Build a dynamic add/remove URL list with heading."""
        self._add_field_heading(parent, label_text, hint_text)

        list_container = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=4)
        parent.pack_start(list_container, False, False, 0)

        def add_url_row(url_text=''):
            row_box = Gtk.Box(spacing=6)
            entry = Gtk.Entry()
            entry.set_hexpand(True)
            entry.set_placeholder_text('https://...')
            entry.set_text(url_text)
            storage_list.append(entry)
            row_box.pack_start(entry, True, True, 0)

            rm_btn = Gtk.Button(label='Remove')
            def on_remove(_b, e=entry, r=row_box):
                if e in storage_list:
                    storage_list.remove(e)
                list_container.remove(r)
                r.destroy()
            rm_btn.connect('clicked', on_remove)
            row_box.pack_start(rm_btn, False, False, 0)

            list_container.pack_start(row_box, False, False, 0)
            list_container.reorder_child(add_btn, -1)
            row_box.show_all()

        add_btn = Gtk.Button(label='+ Add URL')
        add_btn.set_halign(Gtk.Align.START)
        add_btn.connect('clicked', lambda _b: add_url_row())
        list_container.pack_start(add_btn, False, False, 0)

        add_url_row()
        self._add_url_row_funcs = getattr(self, '_add_url_row_funcs', {})
        self._add_url_row_funcs[id(storage_list)] = add_url_row
        return list_container

    def _build_image_drop_zone(self, parent, label_text, hint_text,
                               file_list):
        """Build a DnD image zone with thumbnails inside a bordered box."""
        self._add_field_heading(parent, label_text, hint_text)

        # Bordered frame contains everything — thumbnails + drop area + button
        zone_frame = Gtk.Frame()
        zone_frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        zone_eb = Gtk.EventBox()
        zone_frame.add(zone_eb)
        container = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=6)
        container.set_margin_start(10)
        container.set_margin_end(10)
        container.set_margin_top(10)
        container.set_margin_bottom(10)
        zone_eb.add(container)
        parent.pack_start(zone_frame, False, False, 0)

        # Thumbnail flow box
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_max_children_per_line(6)
        flow.set_min_children_per_line(1)
        flow.set_column_spacing(8)
        flow.set_row_spacing(8)
        flow.set_homogeneous(False)
        container.pack_start(flow, False, False, 0)

        # Drop hint + Add button in a centered row
        hint_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=4)
        hint_box.set_halign(Gtk.Align.CENTER)
        hint_box.set_margin_top(4)
        hint_box.set_margin_bottom(4)
        drop_hint = Gtk.Label()
        drop_hint.set_markup(
            '<small>Drag and drop images here</small>')
        drop_hint.get_style_context().add_class('dim-label')
        hint_box.pack_start(drop_hint, False, False, 0)
        add_btn = Gtk.Button(label='Add Files\u2026')
        add_btn.set_halign(Gtk.Align.CENTER)
        hint_box.pack_start(add_btn, False, False, 0)
        container.pack_start(hint_box, False, False, 0)

        # Enable DnD on the EventBox
        target = Gtk.TargetEntry.new('text/uri-list', 0, 0)
        zone_eb.drag_dest_set(
            Gtk.DestDefaults.ALL, [target], Gdk.DragAction.COPY)

        def refresh():
            for child in flow.get_children():
                flow.remove(child)
            if file_list:
                drop_hint.set_markup(
                    '<small>Drop more images or click Add Files\u2026</small>')
            else:
                drop_hint.set_markup(
                    '<small>Drag and drop images here</small>')
            for fpath in file_list:
                item = Gtk.Box(
                    orientation=Gtk.Orientation.VERTICAL, spacing=2)
                item.set_margin_start(4)
                item.set_margin_end(4)
                # Thumbnail
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        fpath, 72, 72, True)
                    img = Gtk.Image.new_from_pixbuf(pixbuf)
                except Exception:
                    img = Gtk.Image.new_from_icon_name(
                        'image-missing', Gtk.IconSize.DIALOG)
                item.pack_start(img, False, False, 0)
                # Filename
                fname_lbl = Gtk.Label(
                    label=os.path.basename(fpath))
                fname_lbl.set_max_width_chars(10)
                fname_lbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
                fname_lbl.set_xalign(0.5)
                item.pack_start(fname_lbl, False, False, 0)
                # Remove button
                rm_btn = Gtk.Button(label='\u2715')
                rm_btn.set_relief(Gtk.ReliefStyle.NONE)
                def make_remove(fp):
                    def on_rm(_b):
                        file_list.remove(fp)
                        refresh()
                    return on_rm
                rm_btn.connect('clicked', make_remove(fpath))
                item.pack_start(rm_btn, False, False, 0)
                flow.add(item)
            flow.show_all()

        def on_drag_recv(_w, _ctx, _x, _y, data, _info, _time):
            uris = data.get_uris()
            if not uris:
                return
            for uri in uris:
                try:
                    fpath = GLib.filename_from_uri(uri)[0]
                except Exception:
                    continue
                if os.path.isfile(fpath) and fpath not in file_list:
                    file_list.append(fpath)
            refresh()

        zone_eb.connect('drag-data-received', on_drag_recv)

        def on_pick(_b):
            dlg = Gtk.FileChooserDialog(
                title=f'Select {label_text}',
                parent=self, action=Gtk.FileChooserAction.OPEN)
            dlg.set_select_multiple(True)
            dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                            Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
            ff = Gtk.FileFilter()
            ff.set_name('Images')
            for pat in ['*.png', '*.jpg', '*.jpeg', '*.svg',
                        '*.webp', '*.gif']:
                ff.add_pattern(pat)
            dlg.add_filter(ff)
            af = Gtk.FileFilter()
            af.set_name('All Files')
            af.add_pattern('*')
            dlg.add_filter(af)
            resp = dlg.run()
            if resp == Gtk.ResponseType.OK:
                for f in dlg.get_filenames():
                    if f not in file_list:
                        file_list.append(f)
                refresh()
            dlg.destroy()

        add_btn.connect('clicked', on_pick)

        self._file_refresh_funcs = getattr(self, '_file_refresh_funcs', {})
        self._file_refresh_funcs[id(file_list)] = refresh
        return zone_frame

    # ── Section builders ──

    def _build_brand_dna_section(self, parent):
        inner = self._make_section_frame(parent, 'Your Brand')

        self._add_field_heading(
            inner, 'Brand Description',
            'Who are you? Describe your brand\u2019s voice, values, '
            'target audience, and personality.')
        self.brand_dna_tv = self._make_text_area(
            inner,
            placeholder='Voice, values, audience, personality...',
            height=80)

        self._build_image_drop_zone(
            inner, 'Brand Logos',
            'Upload your logo files \u2014 PNG, SVG, or any format.',
            self.brand_logos)

        self._build_image_drop_zone(
            inner, 'Reference Images',
            'Colours, textures, mood boards, style references '
            '\u2014 anything that captures the brand\u2019s look.',
            self.brand_reference_images)

        self._build_url_list(
            inner, 'Brand Websites',
            'Your existing websites, social pages, or online presence.',
            self.brand_url_entries)

        self._add_field_heading(
            inner, 'Brand Notes',
            'Explain any of the media or links you\u2019ve added above '
            '\u2014 provide context, preferences, anything relevant.')
        self.brand_notes_tv = self._make_text_area(
            inner,
            placeholder='E.g. "The second logo is our dark-mode variant" '
            'or "We always use the orange from our brand kit"...',
            height=50)

    def _build_inspirations_section(self, parent):
        inner = self._make_section_frame(parent, 'Inspirations')

        self._build_url_list(
            inner, 'Inspiration Websites',
            'Sites you love the look or feel of \u2014 '
            'design, layout, interactions, anything.',
            self.inspo_url_entries)

        self._build_image_drop_zone(
            inner, 'Reference Images / Screenshots',
            'Screenshots, mockups, or designs that capture '
            'the vibe you\u2019re going for.',
            self.inspo_images)

        self._add_field_heading(
            inner, 'Inspiration Notes',
            'Explain what you like about the references above '
            '\u2014 what to borrow, what to avoid, specific elements.')
        self.inspo_notes_tv = self._make_text_area(
            inner,
            placeholder='E.g. "I love the hero section on site #1" '
            'or "Use a similar nav style but in our brand colours"...',
            height=50)

    def _build_master_prompt_section(self, parent, initial_text):
        inner = self._make_section_frame(parent, 'Master Prompt')

        self._add_field_heading(
            inner, 'What do you want the website to be?',
            'This is your main brief. Describe the site in as much '
            'detail as you can \u2014 pages, features, tone, goals. '
            'Pre-populated from your Mission field.')

        self.master_prompt_tv = self._make_text_area(
            inner,
            placeholder='Describe the website in detail...',
            height=120)
        if initial_text:
            self.master_prompt_tv.get_buffer().set_text(initial_text)

    # ── Data extraction ──

    def _get_tv_text(self, tv):
        buf = tv.get_buffer()
        return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False).strip()

    def get_data(self):
        return {
            'brand_dna': self._get_tv_text(self.brand_dna_tv),
            'brand_logos': list(self.brand_logos),
            'brand_reference_images': list(self.brand_reference_images),
            'brand_urls': [e.get_text().strip() for e in self.brand_url_entries
                           if e.get_text().strip()],
            'brand_notes': self._get_tv_text(self.brand_notes_tv),
            'inspiration_urls': [e.get_text().strip() for e in self.inspo_url_entries
                                 if e.get_text().strip()],
            'inspiration_images': list(self.inspo_images),
            'inspiration_notes': self._get_tv_text(self.inspo_notes_tv),
            'master_prompt': self._get_tv_text(self.master_prompt_tv),
        }

    def _populate_from_data(self, data):
        """Re-populate form from existing brief data."""
        if data.get('brand_dna'):
            self.brand_dna_tv.get_buffer().set_text(data['brand_dna'])
        if data.get('brand_notes'):
            self.brand_notes_tv.get_buffer().set_text(data['brand_notes'])
        if data.get('inspiration_notes'):
            self.inspo_notes_tv.get_buffer().set_text(data['inspiration_notes'])
        if data.get('master_prompt'):
            self.master_prompt_tv.get_buffer().set_text(data['master_prompt'])

        # Logos
        for fpath in data.get('brand_logos', []):
            if fpath not in self.brand_logos:
                self.brand_logos.append(fpath)
        refresh = self._file_refresh_funcs.get(id(self.brand_logos))
        if refresh:
            refresh()

        # Brand reference images
        for fpath in data.get('brand_reference_images', []):
            if fpath not in self.brand_reference_images:
                self.brand_reference_images.append(fpath)
        refresh = self._file_refresh_funcs.get(id(self.brand_reference_images))
        if refresh:
            refresh()

        # Inspiration images
        for fpath in data.get('inspiration_images', []):
            if fpath not in self.inspo_images:
                self.inspo_images.append(fpath)
        refresh = self._file_refresh_funcs.get(id(self.inspo_images))
        if refresh:
            refresh()

        # Brand URLs (clear default empty row, add data rows)
        add_fn = self._add_url_row_funcs.get(id(self.brand_url_entries))
        if add_fn and data.get('brand_urls'):
            # Remove default empty entry
            if (self.brand_url_entries
                    and not self.brand_url_entries[0].get_text().strip()):
                pass  # keep it, user can overwrite
            for url in data['brand_urls']:
                add_fn(url)

        # Inspiration URLs
        add_fn = self._add_url_row_funcs.get(id(self.inspo_url_entries))
        if add_fn and data.get('inspiration_urls'):
            for url in data['inspiration_urls']:
                add_fn(url)


# ════════════════════════════════════════════
#  Main Config Dialog
# ════════════════════════════════════════════

class ConfigDialog(Gtk.Dialog):
    def __init__(self):
        super().__init__(title='SuperTask\u2122', flags=0)
        self.set_default_size(560, -1)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)

        if os.path.exists(ICON_PATH):
            self.set_icon_from_file(ICON_PATH)

        self.add_buttons('Cancel', Gtk.ResponseType.CANCEL,
                         'Launch', Gtk.ResponseType.OK)
        ok_btn = self.get_widget_for_response(Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class('suggested-action')

        # Website brief data — populated via WebsiteBuilderDialog
        self.website_brief_data = None

        content = self.get_content_area()
        content.set_margin_start(20)
        content.set_margin_end(20)
        content.set_margin_top(12)
        content.set_margin_bottom(8)
        content.set_spacing(4)

        title_lbl = Gtk.Label()
        title_lbl.set_markup('<b>Configure your autonomous session</b>')
        title_lbl.set_xalign(0)
        title_lbl.set_margin_bottom(12)
        content.pack_start(title_lbl, False, False, 0)

        grid = Gtk.Grid()
        grid.set_column_spacing(14)
        grid.set_row_spacing(8)
        content.pack_start(grid, False, False, 0)

        row = 0

        # ── Account ──
        self.accounts = get_accounts()
        self.account_combo = self._add_combo_row(grid, row, 'Account', [])
        self._populate_account_combo()
        self.account_combo.connect('changed', self._on_account_changed)
        row += 1

        # ── Plugins Status ──
        plugins_lbl = Gtk.Label(label='Plugins')
        plugins_lbl.set_xalign(1)
        plugins_lbl.set_valign(Gtk.Align.START)
        plugins_lbl.set_margin_top(4)
        plugins_lbl.get_style_context().add_class('dim-label')
        grid.attach(plugins_lbl, 0, row, 1, 1)

        plugins_outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        plugins_outer.set_hexpand(True)

        self.plugin_list_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=2)
        plugins_outer.pack_start(self.plugin_list_box, False, False, 0)

        refresh_box = Gtk.Box(spacing=8)
        refresh_box.set_margin_top(4)
        refresh_btn = Gtk.Button(label='Refresh')
        refresh_btn.set_halign(Gtk.Align.START)
        refresh_btn.connect('clicked', self._on_refresh_plugins)
        refresh_box.pack_start(refresh_btn, False, False, 0)
        self.plugins_summary = Gtk.Label()
        self.plugins_summary.set_xalign(0)
        self.plugins_summary.get_style_context().add_class('dim-label')
        refresh_box.pack_start(self.plugins_summary, True, True, 0)
        plugins_outer.pack_start(refresh_box, False, False, 0)

        grid.attach(plugins_outer, 1, row, 1, 1)
        row += 1

        # Initial plugin check
        self._refresh_plugin_status()

        # ── Mission (multi-line TextView) ──
        lbl = Gtk.Label(label='Mission')
        lbl.set_xalign(1)
        lbl.set_valign(Gtk.Align.START)
        lbl.set_margin_top(4)
        lbl.get_style_context().add_class('dim-label')
        grid.attach(lbl, 0, row, 1, 1)

        mission_frame = Gtk.Frame()
        mission_frame.set_shadow_type(Gtk.ShadowType.IN)
        self.mission_sw = Gtk.ScrolledWindow()
        self.mission_sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.mission_sw.set_min_content_height(28)
        self.mission_sw.set_max_content_height(100)
        self.mission_tv = Gtk.TextView()
        self.mission_tv.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.mission_tv.set_left_margin(6)
        self.mission_tv.set_right_margin(6)
        self.mission_tv.set_top_margin(4)
        self.mission_tv.set_bottom_margin(4)
        self.mission_tv.set_hexpand(True)
        self.mission_buf = self.mission_tv.get_buffer()
        self.mission_buf.connect('changed', self._on_mission_text_changed)
        self.mission_sw.add(self.mission_tv)
        mission_frame.add(self.mission_sw)
        grid.attach(mission_frame, 1, row, 1, 1)
        row += 1

        # ── Working Directory ──
        lbl = Gtk.Label(label='Working Directory')
        lbl.set_xalign(1)
        lbl.get_style_context().add_class('dim-label')
        grid.attach(lbl, 0, row, 1, 1)
        dir_box = Gtk.Box(spacing=6)
        self.dir_entry = Gtk.Entry()
        self.dir_entry.set_hexpand(True)
        self.dir_entry.set_placeholder_text('Leave blank to pick...')
        dir_box.pack_start(self.dir_entry, True, True, 0)
        browse_btn = Gtk.Button(label='Browse')
        browse_btn.connect('clicked', self._on_browse)
        dir_box.pack_start(browse_btn, False, False, 0)
        grid.attach(dir_box, 1, row, 1, 1)
        row += 1

        # ── Separator ──
        grid.attach(Gtk.Separator(), 0, row, 2, 1)
        row += 1

        # ── Variations ──
        self.variations_combo = self._add_combo_row(
            grid, row, 'Variations', ['1', '2', '3'])
        self.variations_combo.connect('changed', self._on_variations_changed)
        row += 1

        # ── Variation 1 (shown when variations >= 2) ──
        self.v1_label = Gtk.Label(label='Variation 1')
        self.v1_label.set_xalign(1)
        self.v1_label.get_style_context().add_class('dim-label')
        self.v1_label.set_no_show_all(True)
        grid.attach(self.v1_label, 0, row, 1, 1)
        self.v1_box = Gtk.Box(spacing=6)
        self.v1_box.set_no_show_all(True)
        self.v1_entry = Gtk.Entry()
        self.v1_entry.set_hexpand(True)
        self.v1_entry.set_placeholder_text('Type a direction or pick a preset...')
        self.v1_box.pack_start(self.v1_entry, True, True, 0)
        v1_preset_btn = Gtk.Button(label='Presets')
        v1_preset_btn.connect('clicked', self._on_pick_preset, self.v1_entry)
        self.v1_box.pack_start(v1_preset_btn, False, False, 0)
        grid.attach(self.v1_box, 1, row, 1, 1)
        row += 1

        # ── Variation 2 (shown when variations >= 3) ──
        self.v2_label = Gtk.Label(label='Variation 2')
        self.v2_label.set_xalign(1)
        self.v2_label.get_style_context().add_class('dim-label')
        self.v2_label.set_no_show_all(True)
        grid.attach(self.v2_label, 0, row, 1, 1)
        self.v2_box = Gtk.Box(spacing=6)
        self.v2_box.set_no_show_all(True)
        self.v2_entry = Gtk.Entry()
        self.v2_entry.set_hexpand(True)
        self.v2_entry.set_placeholder_text('Type a direction or pick a preset...')
        self.v2_box.pack_start(self.v2_entry, True, True, 0)
        v2_preset_btn = Gtk.Button(label='Presets')
        v2_preset_btn.connect('clicked', self._on_pick_preset, self.v2_entry)
        self.v2_box.pack_start(v2_preset_btn, False, False, 0)
        grid.attach(self.v2_box, 1, row, 1, 1)
        row += 1

        # ── Separator ──
        grid.attach(Gtk.Separator(), 0, row, 2, 1)
        row += 1

        # ── Max Cycles ──
        self.cycles_combo = self._add_combo_row(
            grid, row, 'Max Cycles', MAX_CYCLES_OPTIONS)
        row += 1

        # ── Max Iterations ──
        self.iters_combo = self._add_combo_row(
            grid, row, 'Max Iterations', MAX_ITERS_OPTIONS)
        row += 1

        # ── Model ──
        self.model_combo = self._add_combo_row(
            grid, row, 'Model', MODEL_OPTIONS)
        row += 1

        # ── Mode ──
        self.mode_combo = self._add_combo_row(
            grid, row, 'Mode', MODE_OPTIONS)
        self.mode_combo.connect('changed', self._on_mode_changed)
        row += 1

        # ── Website Brief (conditional — only for Website Builder mode) ──
        self.wb_label = Gtk.Label(label='Website Brief')
        self.wb_label.set_xalign(1)
        self.wb_label.get_style_context().add_class('dim-label')
        self.wb_label.set_no_show_all(True)
        grid.attach(self.wb_label, 0, row, 1, 1)

        self.wb_box = Gtk.Box(spacing=8)
        self.wb_box.set_no_show_all(True)
        self.wb_btn = Gtk.Button(label='Open Website Brief...')
        self.wb_btn.connect('clicked', self._on_open_website_brief)
        self.wb_box.pack_start(self.wb_btn, False, False, 0)
        self.wb_status_label = Gtk.Label()
        self.wb_status_label.set_markup('<small>Not configured</small>')
        self.wb_status_label.get_style_context().add_class('dim-label')
        self.wb_box.pack_start(self.wb_status_label, False, False, 0)
        grid.attach(self.wb_box, 1, row, 1, 1)
        row += 1

        # ── Time Limit ──
        self.time_combo = self._add_combo_row(
            grid, row, 'Time Limit', TIME_LIMIT_OPTIONS)
        row += 1

        self.show_all()

        # Hide conditional rows
        self.v1_label.hide()
        self.v1_box.hide()
        self.v2_label.hide()
        self.v2_box.hide()
        self.wb_label.hide()
        self.wb_box.hide()

    def _add_combo_row(self, grid, row, label_text, options):
        lbl = Gtk.Label(label=label_text)
        lbl.set_xalign(1)
        lbl.get_style_context().add_class('dim-label')
        grid.attach(lbl, 0, row, 1, 1)
        combo = Gtk.ComboBoxText()
        combo.set_hexpand(True)
        for opt in options:
            combo.append_text(opt)
        if options:
            combo.set_active(0)
        grid.attach(combo, 1, row, 1, 1)
        return combo

    def _populate_account_combo(self):
        self.account_combo.remove_all()
        for email, plan, config_dir in self.accounts:
            display = f'{email} ({plan})' if plan else email
            self.account_combo.append_text(display)
        self.account_combo.append_text('+ Add Account...')
        if self.accounts:
            self.account_combo.set_active(0)

    def _on_account_changed(self, combo):
        text = combo.get_active_text()
        if text != '+ Add Account...':
            self._refresh_plugin_status()
            return
        combo.handler_block_by_func(self._on_account_changed)

        slot = find_next_slot()
        config_dir = f'{CONFIG_BASE}-{slot}'
        os.makedirs(config_dir, exist_ok=True)
        for sf in ('settings.json', 'settings.local.json'):
            src = os.path.join(DEFAULT_CONFIG, sf)
            dst = os.path.join(config_dir, sf)
            if os.path.exists(src) and not os.path.exists(dst):
                try:
                    os.symlink(src, dst)
                except OSError:
                    pass

        claude_bin = 'claude'
        local_claude = os.path.expanduser('~/.local/bin/claude')
        if os.path.exists(local_claude):
            claude_bin = local_claude

        login_status_file = f'/tmp/supertask-login-{slot}.status'
        try:
            os.unlink(login_status_file)
        except FileNotFoundError:
            pass

        subprocess.Popen([
            'gnome-terminal',
            f'--title=SuperTask\u2122 \u2014 Login Account {slot}',
            '--geometry=80x20',
            '--', 'bash', '-c',
            f'''echo '════════════════════════════════════════════'
echo '  SuperTask™ — Add Account'
echo '════════════════════════════════════════════'
echo ''
echo 'Your browser will open. Sign in with the'
echo 'account you want to add.'
echo ''
CLAUDECODE= CLAUDE_CONFIG_DIR='{config_dir}' '{claude_bin}' auth login
echo ''
if CLAUDECODE= CLAUDE_CONFIG_DIR='{config_dir}' '{claude_bin}' auth status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("loggedIn") else 1)' 2>/dev/null; then
    echo 'LOGIN_OK' > '{login_status_file}'
    echo 'Login successful!'
else
    echo 'LOGIN_FAIL' > '{login_status_file}'
    echo 'Login failed or cancelled.'
fi
echo ''
echo 'This window will close in 3 seconds...'
sleep 3'''
        ])

        wait_dlg = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.NONE,
            text='Logging in...')
        wait_dlg.format_secondary_text(
            'Complete the login in the terminal window that opened.\n'
            'Your browser should have opened automatically.\n\n'
            'This dialog will close when login completes.')
        wait_dlg.add_button('Done', Gtk.ResponseType.OK)

        def check_login():
            if os.path.exists(login_status_file):
                wait_dlg.response(Gtk.ResponseType.OK)
                return False
            return True

        GLib.timeout_add(500, check_login)
        wait_dlg.run()
        wait_dlg.destroy()

        login_ok = False
        if os.path.exists(login_status_file):
            try:
                result = open(login_status_file).read().strip()
                login_ok = (result == 'LOGIN_OK')
            except OSError:
                pass
            try:
                os.unlink(login_status_file)
            except OSError:
                pass

        if login_ok:
            try:
                result = subprocess.run(
                    ['claude', 'auth', 'status', '--json'],
                    capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'CLAUDECODE': '', 'CLAUDE_CONFIG_DIR': config_dir}
                )
                data = json.loads(result.stdout)
                new_email = data.get('email', 'unknown')
                new_plan = data.get('subscriptionType', '')
            except Exception:
                new_email = 'unknown'
                new_plan = ''
            save_account(slot, new_email, new_plan, config_dir)
            self.accounts.append((new_email, new_plan, config_dir))
            self._populate_account_combo()
            self.account_combo.set_active(len(self.accounts) - 1)
            msg = Gtk.MessageDialog(
                transient_for=self, modal=True,
                message_type=Gtk.MessageType.INFO,
                buttons=Gtk.ButtonsType.OK, text='Account added!')
            msg.format_secondary_text(f'{new_email} ({new_plan})')
            msg.run()
            msg.destroy()
        else:
            if self.accounts:
                self.account_combo.set_active(0)
            msg = Gtk.MessageDialog(
                transient_for=self, modal=True,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK, text='Login failed')
            msg.format_secondary_text(
                'Login was cancelled or failed. You can try again\n'
                'by selecting "+ Add Account..." from the dropdown.')
            msg.run()
            msg.destroy()

        self._refresh_plugin_status()
        combo.handler_unblock_by_func(self._on_account_changed)

    def _on_variations_changed(self, combo):
        n = combo.get_active_text()
        try:
            n = int(n)
        except (ValueError, TypeError):
            n = 1

        if n >= 2:
            self.v1_label.set_no_show_all(False)
            self.v1_box.set_no_show_all(False)
            self.v1_label.show()
            self.v1_box.show_all()
        else:
            self.v1_label.hide()
            self.v1_box.hide()
            self.v1_entry.set_text('')

        if n >= 3:
            self.v2_label.set_no_show_all(False)
            self.v2_box.set_no_show_all(False)
            self.v2_label.show()
            self.v2_box.show_all()
        else:
            self.v2_label.hide()
            self.v2_box.hide()
            self.v2_entry.set_text('')

    def _on_mode_changed(self, combo):
        mode = combo.get_active_text()
        if mode == 'Website Builder':
            self.wb_label.set_no_show_all(False)
            self.wb_box.set_no_show_all(False)
            self.wb_label.show()
            self.wb_box.show_all()
        else:
            self.wb_label.hide()
            self.wb_box.hide()

    def _on_open_website_brief(self, _btn):
        mission_text = self._get_mission_text()
        dlg = WebsiteBuilderDialog(
            self,
            initial_master_prompt=mission_text,
            existing_data=self.website_brief_data)
        resp = dlg.run()
        if resp == Gtk.ResponseType.OK:
            self.website_brief_data = dlg.get_data()
            n_logos = len(self.website_brief_data.get('brand_logos', []))
            n_urls = len(self.website_brief_data.get('brand_urls', []))
            n_inspo = len(self.website_brief_data.get('inspiration_urls', []))
            self.wb_status_label.set_markup(
                f'<small>Configured ({n_logos} logos, {n_urls} brand URLs, '
                f'{n_inspo} inspo URLs)</small>')
        dlg.destroy()

    def _on_mission_text_changed(self, buf):
        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)
        line_count = max(1, text.count('\n') + 1)
        target_height = min(max(28, line_count * 24), 120)
        self.mission_sw.set_min_content_height(target_height)

    def _on_browse(self, _btn):
        dlg = Gtk.FileChooserDialog(
            title='Pick your project directory',
            parent=self, action=Gtk.FileChooserAction.SELECT_FOLDER)
        dlg.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        dlg.set_current_folder(os.path.expanduser('~/Desktop'))
        resp = dlg.run()
        if resp == Gtk.ResponseType.OK:
            self.dir_entry.set_text(dlg.get_filename())
        dlg.destroy()

    def _on_pick_preset(self, _btn, target_entry):
        dlg = PresetPickerDialog(self)
        resp = dlg.run()
        if resp == Gtk.ResponseType.OK and dlg.selected_preset:
            target_entry.set_text(dlg.selected_preset)
        dlg.destroy()

    # ── Plugin status methods ──

    def _refresh_plugin_status(self):
        """Clear and rebuild plugin status rows."""
        for child in list(self.plugin_list_box.get_children()):
            self.plugin_list_box.remove(child)
            child.destroy()

        config_dir = self.get_selected_config_dir()
        status = check_plugins(config_dir)
        all_ok = True
        count = 0

        for plugin in REQUIRED_PLUGINS:
            pid = plugin['id']
            ok = status.get(pid, False)
            if ok:
                count += 1
            else:
                all_ok = False

            row_box = Gtk.Box(spacing=8)
            row_box.set_margin_top(1)
            row_box.set_margin_bottom(1)

            icon = Gtk.Label()
            if ok:
                icon.set_markup(
                    '<span foreground="#4CAF50" weight="bold">\u2714</span>')
            else:
                icon.set_markup(
                    '<span foreground="#F44336" weight="bold">\u2718</span>')
            icon.set_width_chars(2)
            row_box.pack_start(icon, False, False, 0)

            name = Gtk.Label()
            esc = GLib.markup_escape_text(plugin['display'])
            if ok:
                name.set_markup(esc)
            else:
                name.set_markup(
                    f'<span foreground="#F44336">{esc}</span>')
            name.set_xalign(0)
            name.set_hexpand(True)
            row_box.pack_start(name, True, True, 0)

            if not ok:
                if plugin['type'] == 'local':
                    btn = Gtk.Button(label='Install')
                    btn.set_tooltip_text('Download and install AutoLoop')
                    btn.connect('clicked', self._on_install_autoloop)
                else:
                    btn = Gtk.Button(label='Copy')
                    btn.set_tooltip_text(plugin['install_cmd'])
                    btn.connect('clicked', self._on_copy_install,
                                plugin['install_cmd'])
                btn.set_relief(Gtk.ReliefStyle.NONE)
                row_box.pack_start(btn, False, False, 0)

            self.plugin_list_box.pack_start(row_box, False, False, 0)

        self._update_plugin_summary(count, len(REQUIRED_PLUGINS))
        self._set_launch_sensitive(all_ok)
        self.plugin_list_box.show_all()

    def _on_refresh_plugins(self, _btn):
        self._refresh_plugin_status()

    def _on_copy_install(self, _btn, install_cmd):
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(install_cmd, -1)
        clipboard.store()

    def _on_install_autoloop(self, btn):
        """Download and install the AutoLoop plugin for the selected account."""
        config_dir = self.get_selected_config_dir()
        target = os.path.join(config_dir, 'plugins', 'autoloop')
        btn.set_sensitive(False)
        btn.set_label('Installing...')

        def do_install():
            try:
                url = ('https://github.com/AdamHoldinPurge/'
                       'autoloop-plugin/archive/refs/heads/master.zip')
                resp = urlopen(url, timeout=30)
                zdata = BytesIO(resp.read())

                with ZipFile(zdata) as zf:
                    prefix = 'autoloop-plugin-master/'
                    os.makedirs(target, exist_ok=True)
                    for member in zf.namelist():
                        if not member.startswith(prefix):
                            continue
                        rel = member[len(prefix):]
                        if not rel:
                            continue
                        dest = os.path.join(target, rel)
                        if member.endswith('/'):
                            os.makedirs(dest, exist_ok=True)
                        else:
                            os.makedirs(os.path.dirname(dest),
                                        exist_ok=True)
                            with zf.open(member) as src, \
                                    open(dest, 'wb') as dst:
                                shutil.copyfileobj(src, dst)

                # Fix marketplace.json to point to this install path
                mkt_file = os.path.join(
                    target, '.claude-plugin', 'marketplace.json')
                os.makedirs(os.path.dirname(mkt_file), exist_ok=True)
                mkt = {
                    'name': 'autoloop-local',
                    'description': 'Local marketplace for autoloop',
                    'plugins': [{
                        'name': 'autoloop',
                        'description': 'Self-planning autonomous loop.',
                        'version': '1.0.0',
                        'source': {'type': 'directory', 'path': target}
                    }]
                }
                with open(mkt_file, 'w') as f:
                    json.dump(mkt, f, indent=2)

                # Make scripts executable
                scripts_dir = os.path.join(target, 'scripts')
                if os.path.isdir(scripts_dir):
                    for fname in os.listdir(scripts_dir):
                        if fname.endswith('.sh'):
                            fp = os.path.join(scripts_dir, fname)
                            os.chmod(fp, 0o755)

                GLib.idle_add(self._install_done, True, '')
            except Exception as e:
                GLib.idle_add(self._install_done, False, str(e))

        threading.Thread(target=do_install, daemon=True).start()

    def _install_done(self, success, error_msg):
        """Called on main thread when autoloop install finishes."""
        if success:
            msg = Gtk.MessageDialog(
                transient_for=self, modal=True,
                message_type=Gtk.MessageType.INFO,
                buttons=Gtk.ButtonsType.OK,
                text='AutoLoop installed!')
            msg.format_secondary_text(
                'The AutoLoop plugin has been downloaded and installed.')
        else:
            msg = Gtk.MessageDialog(
                transient_for=self, modal=True,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text='Install failed')
            msg.format_secondary_text(f'Error: {error_msg}')
        msg.run()
        msg.destroy()
        self._refresh_plugin_status()

    def _update_plugin_summary(self, installed, total):
        if installed == total:
            self.plugins_summary.set_markup(
                f'<small><span foreground="#4CAF50">'
                f'{installed}/{total} installed</span></small>')
        else:
            missing = total - installed
            self.plugins_summary.set_markup(
                f'<small><span foreground="#F44336">'
                f'{missing} missing</span> \u2014 '
                f'install then click Refresh</small>')

    def _set_launch_sensitive(self, sensitive):
        ok_btn = self.get_widget_for_response(Gtk.ResponseType.OK)
        if ok_btn:
            ok_btn.set_sensitive(sensitive)
            if not sensitive:
                ok_btn.set_tooltip_text(
                    'Install all required plugins first')
            else:
                ok_btn.set_tooltip_text(None)

    def get_selected_config_dir(self):
        idx = self.account_combo.get_active()
        if 0 <= idx < len(self.accounts):
            return self.accounts[idx][2]
        return DEFAULT_CONFIG

    def get_account_label(self):
        text = self.account_combo.get_active_text()
        if text and text != '+ Add Account...':
            return text
        if self.accounts:
            email, plan, _ = self.accounts[0]
            return f'{email} ({plan})' if plan else email
        return 'Default'

    def _get_mission_text(self):
        buf = self.mission_tv.get_buffer()
        return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False).strip()

    def get_values(self):
        v1_text = self.v1_entry.get_text().strip()
        v2_text = self.v2_entry.get_text().strip()
        return {
            'account_label': self.get_account_label(),
            'config_dir': self.get_selected_config_dir(),
            'mission': self._get_mission_text(),
            'work_dir': self.dir_entry.get_text().strip(),
            'variations': self.variations_combo.get_active_text() or '1',
            'v2_preset': v1_text if v1_text else 'N/A',
            'v3_preset': v2_text if v2_text else 'N/A',
            'max_cycles': self.cycles_combo.get_active_text() or 'Infinite',
            'max_iters': self.iters_combo.get_active_text() or 'Infinite',
            'model': self.model_combo.get_active_text() or 'opus',
            'mode': self.mode_combo.get_active_text() or 'General',
            'time_limit': self.time_combo.get_active_text() or 'No limit',
        }


def main():
    dlg = ConfigDialog()
    response = dlg.run()

    if response == Gtk.ResponseType.OK:
        vals = dlg.get_values()

        def sanitize(s):
            return s.replace('|', ' \u2014 ').replace('\n', ' ').replace('\r', '')

        # Save website brief to temp file if configured
        brief_path = ''
        if dlg.website_brief_data:
            with tempfile.NamedTemporaryFile(
                    mode='w', suffix='.json', prefix='supertask-brief-',
                    dir='/tmp', delete=False) as f:
                json.dump(dlg.website_brief_data, f, indent=2)
                brief_path = f.name

        # Output pipe-separated values for launcher.sh to parse
        # Fields: account_label|config_dir|mission|work_dir|variations|
        #         v2_preset|v3_preset|max_cycles|max_iters|model|mode|
        #         time_limit|website_brief_path
        parts = [
            sanitize(vals['account_label']),
            vals['config_dir'],
            sanitize(vals['mission']),
            vals['work_dir'],
            vals['variations'],
            sanitize(vals['v2_preset']),
            sanitize(vals['v3_preset']),
            vals['max_cycles'],
            vals['max_iters'],
            vals['model'],
            vals['mode'],
            vals['time_limit'],
            brief_path,
        ]
        print('|'.join(parts))
        dlg.destroy()
        sys.exit(0)
    else:
        dlg.destroy()
        sys.exit(1)


if __name__ == '__main__':
    main()
