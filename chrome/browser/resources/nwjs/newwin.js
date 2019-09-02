//console.log("NWJS/DEFAULT.JS");
var manifest = chrome.runtime.getManifest();
var options = { 'url' : manifest.main, 'type': 'popup' };
var title = null;
console.log("NEWWIN MODE");
if (manifest.window) {
  //if (manifest.window.id)
    //options.tabId = manifest.window.id;
  //options.innerBounds = {};
  if (manifest.window.frame === false)
    options.frameless = true;
  if (manifest.window.resizable === false)
    options.resizable = false;
  if (manifest.window.height)
    options.height = manifest.window.height;
  if (manifest.window.width)
    options.width = manifest.window.width;
  if (manifest.window.min_width)
    options.minWidth = manifest.window.min_width;
  if (manifest.window.max_width)
    options.maxWidth = manifest.window.max_width;
  if (manifest.window.min_height)
    options.minHeight = manifest.window.min_height;
  if (manifest.window.max_height)
    options.maxHeight = manifest.window.max_height;
  if (manifest.window.fullscreen === true)
    options.state = 'fullscreen';
  if (manifest.window.show === false)
    options.hidden = true;
  if (manifest.window.show_in_taskbar === false)
    options.showInTaskbar = false;
  if (manifest.window['always_on_top'] === true)
    options.alwaysOnTop = true;
  if (manifest.window['visible_on_all_workspaces'] === true)
    options.allVisible = true;
  if (manifest.window.titleBarStyle) {
    options.title_bar_style = manifest.window.titleBarStyle;
    if (require('os').platform() == "darwin" &&
        options.title_bar_style &&
        options.title_bar_style.startsWith("hidden") &&
        manifest.window.frame === false) {
      options.frameless = false;
      options.force_enable_drag_region = true;
    }
  }
  if (manifest.window.force_enable_drag_region)
    options.force_enable_drag_region = true;
  if (manifest.window.transparent)
    options.alphaEnabled = true;
  // if (manifest.window.kiosk === true)
  //   options.kiosk = true;
  if (manifest.window.position)
    options.position = manifest.window.position;
  if (manifest.window.title)
    options.title = manifest.window.title;
}

chrome.windows.create(options, function(win) {
  if (require('os').platform() == "darwin" &&
      options.title_bar_style &&
      options.title_bar_style.startsWith("hidden-inset"))
    chrome.windows.setWindowButtonsOffset(win.id);
});
