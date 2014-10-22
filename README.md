**freedesktop.org** menu and desktop files specifications support for the awesome window manager.

## Dependencies

* **Lgi** - Dynamic Lua binding to GObject libraries using GObject-Introspection.
* **radical** -- An extensible menu subsystem for Awesome WM (optional but recommended).

## Install

```bash
git clone https://github.com/mindeunix/freedesktop.git ~/.config/awesome/freedesktop
git clone https://github.com/Elv13/radical.git ~/.config/awesome/radical
```

Add **require** it at the top of your **~/.config/awesome/rc.lua**:

```lua
local freedesktop = require("freedesktop")
```

Then find this line: 
```lua
-- {{{ Mouse bindings
root.buttons(awful.util.table.join(
    awful.button({ }, 3, function () mymainmenu:toggle() end), -- CHANGE THIS LINE
    awful.button({ }, 4, awful.tag.viewnext),
    awful.button({ }, 5, awful.tag.viewprev)
))
```

And replace it to this:
```lua
-- {{{ Mouse bindings
root.buttons(awful.util.table.join(
    awful.button({ }, 3, freedesktop.menu), -- CHANGE THIS LINE
    awful.button({ }, 4, awful.tag.viewnext),
    awful.button({ }, 5, awful.tag.viewprev)
))
```

## Usage

Locating icon:

```lua
emacs_icon = freedesktop.lookup_icon("emacs")
```

Adding a new menu item:

``` lua
freedesktop.categories.Security = {
    { Icon = "burp", Name = "Burp Suite",       Exec = "burp" },
    { Icon = "zap",  Name = "Zed Attack Proxy", Exec = "zap"  }
}
```

![menu](http://i.imgur.com/LBAHkhY.png)
