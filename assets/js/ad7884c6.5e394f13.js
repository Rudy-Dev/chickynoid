"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[644],{10911:function(e){e.exports=JSON.parse('{"functions":[{"name":"new","desc":"Constructs a new ClientChickynoid for the local player, spawning it at the specified\\nposition. The position is just to prevent a mispredict.","params":[{"name":"position","desc":"The position to spawn this character, provided by the server.","lua_type":"Vector3"}],"returns":[{"desc":"","lua_type":"ClientChickynoid"}],"function_type":"static","source":{"line":50,"path":"src/Client/ClientChickynoid/init.lua"}},{"name":"HandleNewState","desc":"The server sends each client an updated world state on a fixed timestep. This\\nhandles state updates for this character.","params":[{"name":"state","desc":"The new state sent by the server.","lua_type":"table"},{"name":"lastConfirmed","desc":"The serial number of the last command confirmed by the server.","lua_type":"number"},{"name":"serverTime","desc":"Time when command was confirmed","lua_type":"number"},{"name":"serverHealthFps","desc":"The current FPS the server is running at","lua_type":"number"},{"name":"networkProblem","desc":"Indicates any known network problem","lua_type":"any"}],"returns":[],"function_type":"method","source":{"line":160,"path":"src/Client/ClientChickynoid/init.lua"}}],"properties":[],"types":[],"name":"ClientChickynoid","desc":"A Chickynoid class that handles character simulation and command generation for the client\\nThere is only one of these for the local player","realm":["Client"],"source":{"line":8,"path":"src/Client/ClientChickynoid/init.lua"}}')}}]);