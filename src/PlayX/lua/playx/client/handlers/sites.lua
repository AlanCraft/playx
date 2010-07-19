-- PlayX
-- Copyright (c) 2009 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

list.Set("PlayXHandlers", "Hulu", function(width, height, start, volume, adjVol, uri, handlerArgs)
    return playxlib.HandlerResult{
        url = uri,
        center = true,
        css = [[
* { overflow: hidden !important; }
]],
        js = [[
var m = document.body.innerHTML.match(/\/embed\/([^"]+)"/);
if (m) {
    document.body.style.overflow = 'hidden';
    var id = m[1];
    document.body.innerHTML = '<div id="player-container"></div>'
    var swfObject = new SWFObject("/embed/" + id, "player", "]] .. width .. [[", "]] .. height .. [[", "10.0.22");
    swfObject.useExpressInstall("/expressinstall.swf");
    swfObject.setAttribute("style", "position:fixed;top:0;left:0;width:1024px;height:512px;z-index:99999;");
    swfObject.addParam("allowScriptAccess", "always");
    swfObject.addParam("allowFullscreen", "true");
    swfObject.addVariable("popout", "true");
    swfObject.addVariable("plugins", "1");
    swfObject.addVariable("modes", 4);
    swfObject.addVariable("initMode", 4);
    swfObject.addVariable("sortBy", "");
    swfObject.addVariable("continuous_play_on", "false");
    swfObject.addVariable("st", ]] .. start .. [[);
    swfObject.addVariable("stage_width", "]] .. width .. [[");
    swfObject.addVariable("stage_height", "]] .. height .. [[");
    swfObject.write("player-container");
} else {
    document.body.innerHTML = 'Failure to detect ID.'
}
]]}
end)

list.Set("PlayXHandlers", "justin.tv", function(width, height, start, volume, adjVol, uri, handlerArgs)
    volume = adjVol -- This handler supports instant volume changing
    
    local volumeFunc = function(volume)
        return [[
try {
  player.change_volume(]] .. volume .. [[);
} catch (e) {}
]]
    end
    
    return playxlib.HandlerResult{
        center = true,
        body = [[<div id="player-container"></div>]],
        js = [[
var player;
var actionInterval;
var script = document.createElement('script');
script.type = 'text/javascript';
script.src = 'http://www-cdn.justin.tv/javascripts/jtv_api.js';
script.onload = function () {
  document.body.style.textAlign = 'center';
  player = jtv_api.new_player("player-container", {channel: "]] .. playxlib.JSEscape(uri) .. [[", custom: true})
  actionInterval = setInterval(function() {
    if (player.play_live) {
      clearInterval(actionInterval);
      player.play_live("]] .. playxlib.JSEscape(uri) .. [[");
      player.change_volume(]] .. volume .. [[);
      var style = window.getComputedStyle(player, null);
      var width = parseInt(style.getPropertyValue("width").replace(/px/, ""));
      var height = parseInt(style.getPropertyValue("height").replace(/px/, ""));
      var useHeight = ]] .. height .. [[;
      var useWidth = ]] .. height .. [[ * width / height;
      player.style.width = useWidth + 'px';
      player.style.height = useHeight + 'px';
      player.resize_player(useWidth, useHeight);
    }
  }, 100);
}
document.body.appendChild(script);
]],
        volumeFunc = volumeFunc}
end)