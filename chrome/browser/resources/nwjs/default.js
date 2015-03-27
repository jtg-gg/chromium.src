//console.log("NWJS/DEFAULT.JS");
var manifest = chrome.runtime.getManifest();
var options = {'id': '.main'};
if (manifest.window) {
  if (manifest.window.frame === false)
    options.frame = 'none';
}
chrome.app.window.create(manifest.main, options);