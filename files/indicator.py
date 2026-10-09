#!/usr/bin/python3
"""Floating "listening" bar for dictation: a Wayland layer-shell overlay at the
top of the screen with keyboard interactivity disabled, so it can never take
focus from the app being dictated into. Reads state lines ("listening") on
stdin and exits when stdin closes, so it can't outlive the dictation process
that started it. Runs under system Python (needs python3-gi + gtk4-layer-shell)."""
import os
import sys

# Debian package, Fedora/RHEL package, or a source build under /usr/local (AlmaLinux).
LIB_DIRS = ["/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/usr/local/lib64", "/usr/local/lib"]
LIB_NAME = "libgtk4-layer-shell.so.0"


def find_layer_shell_dir() -> "str | None":
    for d in LIB_DIRS:
        if os.path.exists(os.path.join(d, LIB_NAME)):
            return d
    return None


# Without layer-shell the bar would be an ordinary window that can take keyboard focus
# from the app being dictated into, so on X11 (or anything non-Wayland) show nothing.
if "--check" not in sys.argv and not os.environ.get("WAYLAND_DISPLAY"):
    sys.exit("indicator: not a Wayland session - bar disabled (tray icon still shows status)")

# gtk4-layer-shell must load before libwayland-client, which from Python means LD_PRELOAD.
if LIB_NAME not in os.environ.get("LD_PRELOAD", ""):
    lib_dir = find_layer_shell_dir()
    if lib_dir is None:
        sys.exit(f"indicator: {LIB_NAME} not found in {LIB_DIRS}")
    env = dict(os.environ, LD_PRELOAD=os.path.join(lib_dir, LIB_NAME))
    typelib_dir = os.path.join(lib_dir, "girepository-1.0")
    if os.path.isdir(typelib_dir):
        env["GI_TYPELIB_PATH"] = ":".join(p for p in [typelib_dir, os.environ.get("GI_TYPELIB_PATH", "")] if p)
    os.execve(sys.executable, [sys.executable, *sys.argv], env)

import gi  # noqa: E402

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

if "--check" in sys.argv:
    print(f"indicator: layer-shell {LayerShell.get_major_version()}.{LayerShell.get_minor_version()} OK")
    sys.exit(0)

CSS = b"""
window { background: transparent; }
.pill { background: rgba(28, 28, 30, 0.90); border-radius: 18px; padding: 6px 16px; }
.dot { color: #8e8e93; font-size: 15px; }
.dot.live { color: #ff3b30; animation: pulse 1.2s ease-in-out infinite; }
.title { color: #ffffff; font-weight: bold; }
.hint { color: #c7c7cc; font-size: smaller; }
@keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.3; } 100% { opacity: 1; } }
"""


def build_window(app: Gtk.Application) -> None:
    if not LayerShell.is_supported():
        print("indicator: compositor lacks layer-shell - bar disabled", file=sys.stderr)
        app.quit()
        return
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

    win = Gtk.Window(application=app)
    win.set_decorated(False)
    win.set_resizable(False)

    LayerShell.init_for_window(win)
    LayerShell.set_namespace(win, "voice-dictation")
    LayerShell.set_layer(win, LayerShell.Layer.OVERLAY)
    LayerShell.set_anchor(win, LayerShell.Edge.TOP, True)
    LayerShell.set_margin(win, LayerShell.Edge.TOP, 10)
    LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.NONE)

    pill = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    pill.add_css_class("pill")
    dot = Gtk.Label(label="●")
    dot.add_css_class("dot")
    title = Gtk.Label(label="Loading dictation…")
    title.add_css_class("title")
    hint = Gtk.Label(label="")
    hint.add_css_class("hint")
    for widget in (dot, title, hint):
        pill.append(widget)
    win.set_child(pill)

    def on_stdin(_fd, _condition):
        line = sys.stdin.readline()
        if not line:
            app.quit()
            return False
        if line.strip() == "listening":
            dot.add_css_class("live")
            title.set_label("Listening")
            hint.set_label("Win+H or any key to stop")
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_stdin)
    win.present()


def main() -> None:
    app = Gtk.Application(application_id=None, flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", build_window)
    app.run([sys.argv[0]])


if __name__ == "__main__":
    main()
