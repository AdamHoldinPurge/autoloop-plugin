#!/usr/bin/env python3
"""SuperTask™ — GTK3 Monitor Application
Supports multi-variant mode with round-robin creative variations."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gtk, GLib, Pango
import os
import sys
import re
import signal
import subprocess
import time as _time
from pathlib import Path
from datetime import datetime


class AutoloopMonitor(Gtk.Window):
    def __init__(self, work_dir, loop_pid=None):
        super().__init__()
        self.work_dir = work_dir
        self.loop_pid = loop_pid
        self.log_dir = os.path.join(work_dir, 'autoloop-logs')
        self.status_file = os.path.join(self.log_dir, 'STATUS')
        self.stop_signal_file = os.path.join(self.log_dir, 'STOP_SIGNAL')
        self.current_variant_file = os.path.join(self.log_dir, 'CURRENT_VARIANT')
        self.stopping = False
        self._last_history = ''

        # Variant info — populated from SESSION file
        self.num_variants = 1
        self.variant_presets = {}
        self.account_label = ''
        self._session_loaded = False

        # Plan/history paths depend on variant mode — set after session load
        self.plan_file = os.path.join(work_dir, 'PLAN.md')
        self.history_file = os.path.join(work_dir, 'autoloop-logs', 'history.log')

        self.set_default_size(460, 580)
        self.set_position(Gtk.WindowPosition.CENTER)

        icon_path = os.path.expanduser('~/.claude/plugins/autoloop/icon.png')
        if os.path.exists(icon_path):
            self.set_icon_from_file(icon_path)

        self._build_ui()

        GLib.timeout_add_seconds(3, self._refresh)
        GLib.timeout_add(150, self._pulse)
        self._refresh()

        self.connect('delete-event', self._on_close)
        self.connect('destroy', self._on_destroy)

        # Handle SIGTERM/SIGINT so external kills still clean up
        signal.signal(signal.SIGTERM, self._on_signal)
        signal.signal(signal.SIGINT, self._on_signal)

    def _build_ui(self):
        # Header bar
        hb = Gtk.HeaderBar()
        hb.set_show_close_button(True)
        hb.set_title('SuperTask\u2122')
        hb.set_has_subtitle(True)
        hb.set_subtitle('Starting\u2026')
        self.header_bar = hb

        self.stop_btn = Gtk.Button(label='Stop')
        self.stop_btn.get_style_context().add_class('destructive-action')
        self.stop_btn.connect('clicked', self._on_stop)
        hb.pack_end(self.stop_btn)

        self.set_titlebar(hb)

        # Main content
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(box)

        # ── Mission ──
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        frame.set_margin_start(16)
        frame.set_margin_end(16)
        frame.set_margin_top(14)
        frame.set_margin_bottom(6)

        self.lbl_account = Gtk.Label()
        self.lbl_account.set_xalign(0)
        self.lbl_account.set_markup('<small><b>Account:</b> \u2014</small>')
        frame.pack_start(self.lbl_account, False, False, 0)

        self.lbl_mission = Gtk.Label()
        self.lbl_mission.set_xalign(0)
        self.lbl_mission.set_line_wrap(True)
        self.lbl_mission.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.lbl_mission.set_max_width_chars(54)
        self.lbl_mission.set_markup('<b>Mission:</b> \u2014')
        frame.pack_start(self.lbl_mission, False, False, 0)

        self.lbl_meta = Gtk.Label()
        self.lbl_meta.set_xalign(0)
        self.lbl_meta.set_markup('<small>Cycle 0 \u00b7 Iteration 0</small>')
        frame.pack_start(self.lbl_meta, False, False, 0)

        self.lbl_time = Gtk.Label()
        self.lbl_time.set_xalign(0)
        self.lbl_time.set_markup('<small>No time limit</small>')
        frame.pack_start(self.lbl_time, False, False, 0)

        # Variant indicator — hidden when single variant
        self.lbl_variant = Gtk.Label()
        self.lbl_variant.set_xalign(0)
        self.lbl_variant.set_markup('')
        self.lbl_variant.set_no_show_all(True)
        self.lbl_variant.hide()
        frame.pack_start(self.lbl_variant, False, False, 0)

        box.pack_start(frame, False, False, 0)

        # ── Task progress ──
        pbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        pbox.set_margin_start(16)
        pbox.set_margin_end(16)
        pbox.set_margin_top(4)
        pbox.set_margin_bottom(8)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_text('0 / 0 tasks')
        pbox.pack_start(self.progress, False, False, 0)

        box.pack_start(pbox, False, False, 0)

        # ── Separator ──
        box.pack_start(Gtk.Separator(), False, False, 0)

        # ── Current task ──
        tbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        tbox.set_margin_start(16)
        tbox.set_margin_end(16)
        tbox.set_margin_top(10)
        tbox.set_margin_bottom(6)

        lbl = Gtk.Label()
        lbl.set_xalign(0)
        lbl.set_markup('<b>Current Task</b>')
        tbox.pack_start(lbl, False, False, 0)

        self.lbl_task = Gtk.Label()
        self.lbl_task.set_xalign(0)
        self.lbl_task.set_line_wrap(True)
        self.lbl_task.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.lbl_task.set_max_width_chars(54)
        self.lbl_task.set_text('Waiting\u2026')
        tbox.pack_start(self.lbl_task, False, False, 2)

        self.activity = Gtk.ProgressBar()
        self.activity.set_size_request(-1, 6)
        tbox.pack_start(self.activity, False, False, 4)

        self.lbl_status = Gtk.Label()
        self.lbl_status.set_xalign(0)
        self.lbl_status.set_markup('<small>\u2014</small>')
        tbox.pack_start(self.lbl_status, False, False, 0)

        box.pack_start(tbox, False, False, 0)

        # ── Separator ──
        box.pack_start(Gtk.Separator(), False, False, 4)

        # ── Recent activity ──
        hlbl = Gtk.Label()
        hlbl.set_xalign(0)
        hlbl.set_markup('<b>Recent Activity</b>')
        hlbl.set_margin_start(16)
        hlbl.set_margin_top(6)
        box.pack_start(hlbl, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_margin_start(16)
        sw.set_margin_end(16)
        sw.set_margin_top(4)
        sw.set_margin_bottom(8)

        self.history_box = Gtk.ListBox()
        self.history_box.set_selection_mode(Gtk.SelectionMode.NONE)
        sw.add(self.history_box)

        box.pack_start(sw, True, True, 0)

    # ── Variant helpers ──

    def _get_variant_dir(self, v):
        if self.num_variants == 1:
            return self.work_dir
        return os.path.join(self.work_dir, f'variant_{v}')

    def _get_variant_plan(self, v):
        return os.path.join(self._get_variant_dir(v), 'PLAN.md')

    def _get_variant_history(self, v):
        if self.num_variants == 1:
            return os.path.join(self.log_dir, 'history.log')
        return os.path.join(self._get_variant_dir(v), 'autoloop-logs', 'history.log')

    def _get_current_variant(self):
        """Read which variant is currently being worked on."""
        if not os.path.exists(self.current_variant_file):
            return 1
        try:
            return int(Path(self.current_variant_file).read_text().strip())
        except (ValueError, OSError):
            return 1

    # ── Polling ──

    def _pulse(self):
        if not self.stopping and self._loop_alive():
            self.activity.pulse()
        return True

    def _refresh(self):
        self._read_session()
        self._read_variant_indicator()
        self._read_plan_aggregate()
        self._read_status()
        self._read_history_aggregate()
        self._check_alive()
        return True

    def _loop_alive(self):
        if not self.loop_pid:
            return False
        try:
            os.kill(self.loop_pid, 0)
            return True
        except (ProcessLookupError, PermissionError):
            return False

    def _check_alive(self):
        alive = self._loop_alive()
        if self.stopping:
            if not alive:
                self.header_bar.set_subtitle('Stopped')
                self.stop_btn.set_sensitive(False)
                self.activity.set_fraction(1.0)
            elif os.path.exists(self.stop_signal_file):
                self.header_bar.set_subtitle('Stopping\u2026')
            else:
                self.header_bar.set_subtitle('Stopped')
                self.stop_btn.set_sensitive(False)
                self.activity.set_fraction(1.0)
        elif not alive:
            # Distinguish error from success
            status = self._get_exit_status()
            self.header_bar.set_subtitle(status)
            self.stop_btn.set_sensitive(False)
            self.activity.set_fraction(1.0)
            if 'Error' in status:
                self.lbl_task.set_text(self._get_error_detail())

    def _get_exit_status(self):
        """Check if loop ended successfully or with an error."""
        # Check if any PLAN.md exists
        has_plan = False
        for v in range(1, self.num_variants + 1):
            if os.path.exists(self._get_variant_plan(v)):
                has_plan = True
                break
        if not has_plan:
            return 'Error \u2014 No PLAN.md'

        # Check STATUS file for clues
        if os.path.exists(self.status_file):
            try:
                st = Path(self.status_file).read_text().strip()
                if st.lower() in ('stopped', 'finished', 'all cycles complete'):
                    return 'Finished'
                if 'error' in st.lower() or 'fail' in st.lower():
                    return f'Error \u2014 {st}'
            except OSError:
                pass

        # Check terminal.log for errors
        term_log = os.path.join(self.log_dir, 'terminal.log')
        if os.path.exists(term_log):
            try:
                lines = Path(term_log).read_text().strip().splitlines()
                for line in reversed(lines[-10:]):
                    clean = re.sub(r'\x1b\[[0-9;]*m', '', line).strip()
                    if 'no plan' in clean.lower() or 'error' in clean.lower():
                        return 'Error \u2014 Loop failed'
            except OSError:
                pass
        return 'Finished'

    def _get_error_detail(self):
        """Extract a human-readable error from terminal.log."""
        term_log = os.path.join(self.log_dir, 'terminal.log')
        if os.path.exists(term_log):
            try:
                lines = Path(term_log).read_text().strip().splitlines()
                for line in reversed(lines[-10:]):
                    clean = re.sub(r'\x1b\[[0-9;]*m', '', line).strip()
                    if clean and '[autoloop' in clean:
                        m = re.search(r'\]\s*(.+)', clean)
                        return m.group(1) if m else clean
            except OSError:
                pass
        return 'Check autoloop-logs/terminal.log for details'

    def _read_session(self):
        session_file = os.path.join(self.log_dir, 'SESSION')
        if not os.path.exists(session_file):
            return
        try:
            data = {}
            for line in Path(session_file).read_text().splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    data[k.strip()] = v.strip()

            # Load variant + account info (once)
            if not self._session_loaded:
                self.num_variants = int(data.get('NUM_VARIANTS', '1'))
                for i in range(1, 4):
                    p = data.get(f'VARIANT_{i}_PRESET', '')
                    if p:
                        self.variant_presets[i] = p
                self.account_label = data.get('ACCOUNT', '')
                if self.account_label:
                    self.lbl_account.set_markup(
                        '<small><b>Account:</b> '
                        + GLib.markup_escape_text(self.account_label)
                        + '</small>')
                else:
                    self.lbl_account.set_markup(
                        '<small><b>Account:</b> Default</small>')
                self._session_loaded = True

            start = int(data.get('START_TIME', 0))
            limit = int(data.get('TIME_LIMIT', 0))

            # Elapsed time (freeze if loop ended)
            end = int(data.get('END_TIME', 0))
            if end > 0:
                elapsed = max(0, end - start)
            else:
                elapsed = max(0, int(_time.time()) - start)
            eh = elapsed // 3600
            em = (elapsed % 3600) // 60
            if eh > 0:
                elapsed_str = f'{eh}h {em}m'
            else:
                elapsed_str = f'{em}m'

            if limit == 0:
                self.lbl_time.set_markup(
                    f'<small>Running for {elapsed_str} \u00b7 No time limit</small>')
                return

            remaining = max(0, limit - elapsed)
            rh = remaining // 3600
            rm = (remaining % 3600) // 60
            if remaining <= 0:
                self.lbl_time.set_markup(
                    f'<small>Running for {elapsed_str} \u00b7 Time limit reached</small>')
            elif rh > 0:
                self.lbl_time.set_markup(
                    f'<small>Running for {elapsed_str} \u00b7 {rh}h {rm}m remaining</small>')
            else:
                self.lbl_time.set_markup(
                    f'<small>Running for {elapsed_str} \u00b7 {rm}m remaining</small>')
        except (ValueError, KeyError, OSError):
            pass

    def _read_variant_indicator(self):
        """Show which variant is currently active."""
        if self.num_variants <= 1:
            self.lbl_variant.hide()
            return

        cv = self._get_current_variant()
        preset = self.variant_presets.get(cv, 'Unknown')
        self.lbl_variant.set_markup(
            f'<small><b>Variant {cv} of {self.num_variants}</b> \u2014 {GLib.markup_escape_text(preset)}</small>')
        self.lbl_variant.show()

    def _read_plan_aggregate(self):
        """Read task progress from all variant PLAN.md files."""
        total_done = 0
        total_pending = 0
        first_pending_task = None
        mission_text = None
        cycle_str = '0'
        iter_str = '0'

        for v in range(1, self.num_variants + 1):
            plan_path = self._get_variant_plan(v)
            if not os.path.exists(plan_path):
                continue
            try:
                text = Path(plan_path).read_text()
            except OSError:
                continue

            # Mission (take from first variant)
            if mission_text is None:
                m = re.search(r'## Mission\s*\n(.+?)(?=\n##|\Z)', text, re.DOTALL)
                if m:
                    mission_text = m.group(1).strip()

            # Tasks
            done = len(re.findall(
                r'^\s*\d+\.\s*\[x\]', text, re.MULTILINE | re.IGNORECASE))
            pending = re.findall(
                r'^\s*\d+\.\s*\[ \]\s*(.+)', text, re.MULTILINE)
            total_done += done
            total_pending += len(pending)

            # First pending task from current variant
            if first_pending_task is None and pending:
                cv = self._get_current_variant()
                if v == cv:
                    prefix = f'[V{v}] ' if self.num_variants > 1 else ''
                    first_pending_task = prefix + pending[0].strip()

            # Meta (accumulate highest values)
            cyc = re.search(r'Cycles:\s*(\d+)', text)
            itr = re.search(r'Iterations:\s*(\d+)', text)
            if cyc and int(cyc.group(1)) > int(cycle_str):
                cycle_str = cyc.group(1)
            if itr and int(itr.group(1)) > int(iter_str):
                iter_str = itr.group(1)

        # If no pending task from current variant, grab from any variant
        if first_pending_task is None:
            for v in range(1, self.num_variants + 1):
                plan_path = self._get_variant_plan(v)
                if not os.path.exists(plan_path):
                    continue
                try:
                    text = Path(plan_path).read_text()
                except OSError:
                    continue
                pending = re.findall(
                    r'^\s*\d+\.\s*\[ \]\s*(.+)', text, re.MULTILINE)
                if pending:
                    prefix = f'[V{v}] ' if self.num_variants > 1 else ''
                    first_pending_task = prefix + pending[0].strip()
                    break

        # Update UI
        if mission_text:
            if len(mission_text) > 180:
                mission_text = mission_text[:177] + '\u2026'
            self.lbl_mission.set_markup(
                '<b>Mission:</b> ' + GLib.markup_escape_text(mission_text))

        total = total_done + total_pending
        if total:
            self.progress.set_fraction(total_done / total)
            suffix = f' (across {self.num_variants} variants)' if self.num_variants > 1 else ''
            self.progress.set_text(f'{total_done} / {total} tasks{suffix}')

        if first_pending_task:
            self.lbl_task.set_text(first_pending_task)
        elif total_done > 0:
            self.lbl_task.set_text('All tasks complete \u2014 replanning\u2026')

        self.lbl_meta.set_markup(f'<small>Cycle {cycle_str} \u00b7 Iteration {iter_str}</small>')

    def _read_status(self):
        if not os.path.exists(self.status_file):
            return
        try:
            st = Path(self.status_file).read_text().strip()
        except OSError:
            return
        if st:
            self.lbl_status.set_markup(
                '<small>' + GLib.markup_escape_text(st) + '</small>')
            if not self.stopping:
                self.header_bar.set_subtitle(st)

    def _read_history_aggregate(self):
        """Read history from all variant directories, merge and display."""
        all_lines = []

        for v in range(1, self.num_variants + 1):
            hist_path = self._get_variant_history(v)
            if not os.path.exists(hist_path):
                continue
            try:
                raw = Path(hist_path).read_text()
            except OSError:
                continue
            for line in raw.splitlines():
                line = line.strip()
                if not line:
                    continue
                if self.num_variants > 1:
                    # Prefix with variant tag if not already prefixed
                    if not line.startswith(f'[V{v}]'):
                        # Try to insert after timestamp
                        m = re.match(r'^(\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\])\s*(.*)', line)
                        if m:
                            line = f'{m.group(1)} [V{v}] {m.group(2)}'
                        else:
                            line = f'[V{v}] {line}'
                all_lines.append(line)

        # Build combined text for change detection
        combined = '\n'.join(all_lines)
        if combined == self._last_history:
            return
        self._last_history = combined

        for child in self.history_box.get_children():
            self.history_box.remove(child)

        # Sort by timestamp if possible, otherwise just show in order
        # Lines start with [YYYY-MM-DD HH:MM:SS] so lexicographic sort works
        all_lines.sort()

        for line in reversed(all_lines[-30:]):
            row = Gtk.ListBoxRow()
            lbl = Gtk.Label()
            lbl.set_xalign(0)
            lbl.set_line_wrap(True)
            lbl.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
            lbl.set_max_width_chars(54)
            lbl.set_markup(
                '<small>' + GLib.markup_escape_text(line) + '</small>')
            lbl.set_margin_top(1)
            lbl.set_margin_bottom(1)
            row.add(lbl)
            self.history_box.add(row)

        self.history_box.show_all()

    # ── Actions ──

    def _on_stop(self, _btn):
        """Graceful stop — write STOP_SIGNAL, let loop finish current task and polish."""
        dlg = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text='Stop SuperTask\u2122?')
        if self.num_variants > 1:
            dlg.format_secondary_text(
                f'Claude will finish its current task, polish all {self.num_variants} variants, and exit.')
        else:
            dlg.format_secondary_text(
                'Claude will finish its current task, polish everything, and exit.')
        resp = dlg.run()
        dlg.destroy()
        if resp == Gtk.ResponseType.OK:
            self._do_graceful_stop()

    def _do_graceful_stop(self):
        """Write STOP_SIGNAL for graceful shutdown (loop finishes + polishes)."""
        self.stopping = True
        self.stop_btn.set_label('Stopping\u2026')
        self.stop_btn.set_sensitive(False)
        self.lbl_task.set_text('Finishing up and polishing\u2026')
        self.header_bar.set_subtitle('Stopping\u2026')
        os.makedirs(self.log_dir, exist_ok=True)
        with open(self.stop_signal_file, 'w') as f:
            f.write('STOP requested at '
                    + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + '\n')

    def _on_close(self, _w, _e):
        """Window close — hard kill everything if loop is still running."""
        if self.stopping or not self._loop_alive():
            return False  # allow close → triggers destroy → Gtk.main_quit

        dlg = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text='Cancel SuperTask\u2122?')
        dlg.format_secondary_text(
            'This will immediately stop the loop and kill all running processes.\n'
            'Any in-progress work will be interrupted.')
        dlg.add_button('Yes, cancel everything', Gtk.ResponseType.YES)
        dlg.add_button('Keep running', Gtk.ResponseType.NO)
        resp = dlg.run()
        dlg.destroy()

        if resp == Gtk.ResponseType.YES:
            self._kill_process_tree()
            return False  # allow close → triggers destroy → Gtk.main_quit
        return True  # don't close

    def _on_destroy(self, _w):
        """Window destroyed — ensure everything is cleaned up and GTK exits."""
        if self._loop_alive():
            self._kill_process_tree()
        Gtk.main_quit()

    def _on_signal(self, signum, _frame):
        """Handle SIGTERM/SIGINT — clean up and exit."""
        if self._loop_alive():
            self._kill_process_tree()
        Gtk.main_quit()

    def _collect_descendants(self, pid):
        """Recursively collect all descendant PIDs of a process."""
        descendants = []
        try:
            result = subprocess.run(
                ['pgrep', '-P', str(pid)],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.strip().split('\n'):
                line = line.strip()
                if line:
                    child_pid = int(line)
                    descendants.append(child_pid)
                    descendants.extend(self._collect_descendants(child_pid))
        except (subprocess.TimeoutExpired, ValueError, OSError):
            pass
        return descendants

    def _kill_process_tree(self):
        """Hard kill loop.sh and ALL its child processes (claude, timeout, etc)."""
        if not self.loop_pid:
            return

        # Collect entire process tree (children, grandchildren, etc)
        all_pids = self._collect_descendants(self.loop_pid)
        all_pids.append(self.loop_pid)

        # SIGTERM everything first (graceful)
        for pid in all_pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass

        # Brief wait for processes to exit
        _time.sleep(1)

        # SIGKILL any survivors
        for pid in all_pids:
            try:
                os.kill(pid, 0)  # check if still alive
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass

        # Clean up lockfiles
        try:
            for lockfile in Path('/tmp').glob('autoloop-*.lock'):
                try:
                    lock_pid = int(lockfile.read_text().strip())
                    if lock_pid == self.loop_pid:
                        lockfile.unlink(missing_ok=True)
                        lock_dir = Path(str(lockfile) + '.dir')
                        if lock_dir.exists():
                            lock_dir.unlink(missing_ok=True)
                except (ValueError, OSError):
                    pass
        except OSError:
            pass

        # Clean up signal files
        try:
            stop_f = Path(self.stop_signal_file)
            if stop_f.exists():
                stop_f.unlink(missing_ok=True)
        except OSError:
            pass


def main():
    work_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    pid = int(sys.argv[2]) if len(sys.argv) > 2 else None
    win = AutoloopMonitor(work_dir, pid)
    win.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
