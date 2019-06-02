local computer = computer or require("computer")

if computer.getArchitecture() == "Lua 5.3" then
 return require("colorlib53")
else
 return require("colorlib52")
end