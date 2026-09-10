# Documents and desk accessories — the GUI apps that are launched from the
# launcher rather than bound to a key or wired into a feature module. Anything
# with a keybind belongs in hyprland.nix (nautilus), anything that exists to
# serve one subsystem belongs with it (gnome-calendar, in calendar.nix).
#
# libreoffice-fresh is the GTK build — the stable path on wlroots/Hyprland (the
# Qt6 VCL backend has Wayland scroll/scaling issues).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    libreoffice-fresh
    # gnome-calculator over qalculate-gtk: it is GTK4/libadwaita like the rest of
    # the GNOME apps here, so Stylix's gtk target colours it to match instead of
    # leaving one unstyled window, and it still covers unit/currency conversion
    # and programming mode. No keybind — fuzzel finds it from its .desktop file.
    gnome-calculator
  ];

  # If rendering ever looks blurry/laggy on Hyprland, force the GTK VCL plugin:
  # home.sessionVariables.SAL_USE_VCLPLUGIN = "gtk3";
}
