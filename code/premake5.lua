xpcall(function()
newoption {
	trigger     = "builddir",
	value       = "path",
	description = "Output directory for build/ files."
}

newoption {
	trigger     = "bindir",
	value       = "path",
	description = "Root directory for bin/ files."
}

dofile('tools/build/init.lua')

-- perform component processing
if _OPTIONS['game'] == 'dummy' then
	return
end

root_cwd = os.getcwd()

-- initialize components
dofile('components/config.lua')
dofile('vendor/config.lua')

load_privates('privates_config.lua')

component
{
	name = 'platform:' .. os.get(),
	rawName = os.get(),
	vendor = { dummy = true }
}

workspace "CitizenMP"
	configurations { "Debug", "Release" }

	symbols "On"
	characterset "Unicode"

	flags { "No64BitChecks" }

	flags { "NoIncrementalLink", "NoEditAndContinue", "NoMinimalRebuild" } -- this breaks our custom section ordering in citilaunch, and is kind of annoying otherwise

	includedirs {
		"shared/",
		"client/shared/",
		"../vendor/jitasm/",
		"../vendor/rapidjson/include/",
		"../vendor/fmtlib/",
		"deplibs/include/",
		os.getenv("BOOST_ROOT")
	}

	defines { "GTEST_HAS_PTHREAD=0", "BOOST_ALL_NO_LIB" }

	defines { "_HAS_AUTO_PTR_ETC" } -- until boost gets fixed

	libdirs { "deplibs/lib/" }

	location ((_OPTIONS['builddir'] or "build/") .. _OPTIONS['game'])

	if os.is('windows') then
		buildoptions '/std:c++latest'

		systemversion '10.0.15063.0'
	end

	-- special build dirs for FXServer
	if _OPTIONS['game'] == 'server' then
		location ((_OPTIONS['builddir'] or "build/") .. "server/" .. os.get())
		architecture 'x64'
		defines 'IS_FXSERVER'
	end

	local binroot = ((_OPTIONS['bindir'] or "bin/") .. _OPTIONS['game']) .. '/'

	if _OPTIONS['game'] == 'server' then
		binroot = (_OPTIONS['bindir'] or "bin/") .. 'server/' .. os.get() .. '/'
	end

	-- debug output
	configuration "Debug*"
		targetdir (binroot .. "/debug")
		defines "NDEBUG"

		-- this slows down the application a lot
		defines { '_ITERATOR_DEBUG_LEVEL=0' }

		-- allow one level of inlining
		if os.is('windows') then
			buildoptions '/Ob1'
		end

	-- release output
	configuration "Release*"
		targetdir (binroot .. "/release")
		defines "NDEBUG"
		optimize "Speed"

	configuration "game=five"
		defines "GTA_FIVE"

		filter 'language:C or language:C++'
			architecture 'x64'

	configuration "windows"
		links { "winmm" }

	configuration "not windows"
		buildoptions {
			"-fPIC", -- required to link on AMD64
		}

		links { "c++" }

	-- TARGET: launcher
	if _OPTIONS['game'] ~= 'server' then
		-- game launcher
		include 'client/launcher'
		include 'client/console'
	else
		include 'server/launcher'
	end

	-- TARGET: corert
	include 'client/citicore'

if _OPTIONS['game'] ~= 'server' then
	project "CitiGame"
		targetname "CitizenGame"
		language "C++"
		kind "SharedLib"

		includedirs { 'client/citicore/' }

		files
		{
			"client/common/Error.cpp",
			"client/citigame/Launcher.cpp",
			"client/common/StdInc.cpp"
		}

		links { "Shared", "citicore" }

		defines "COMPILING_GAME"

		pchsource "client/common/StdInc.cpp"
		pchheader "StdInc.h"
end

if os.is('windows') then
	project "CitiMono"
		targetname "CitizenFX.Core"
		language "C#"
		kind "SharedLib"

		flags { 'Unsafe' }

		files { "client/clrcore/*.cs", "client/clrcore/Math/*.cs" }

		if _OPTIONS['game'] ~= 'server' then
			files { "client/clrcore/External/*.cs" }
		end

		links { "System", "Microsoft.CSharp", "../data/client/citizen/clr2/lib/mono/4.5/MsgPack.dll" }

		configuration "Debug*"
			targetdir (binroot .. '/debug/citizen/clr2/lib/mono/4.5/')

		configuration "Release*"
			targetdir (binroot .. '/release/citizen/clr2/lib/mono/4.5/')
end

	group ""

	-- TARGET: shared component
	include "client/shared"

	group "vendor"

if _OPTIONS['game'] ~= 'server' then
	project "libcef_dll"
		targetname "libcef_dll_wrapper"
		language "C++"
		kind "StaticLib"

		defines { "USING_CEF_SHARED", "NOMINMAX", "WIN32", "WRAPPING_CEF_SHARED" }

		flags { "NoIncrementalLink", "NoMinimalRebuild" }

		includedirs { ".", "../vendor/cef" }

		buildoptions "/MP"

		files
		{
			"../vendor/cef/libcef_dll/**.cc",
			"../vendor/cef/libcef_dll/**.cpp",
			"../vendor/cef/libcef_dll/**.h"
		}
end

	-- run components
	group "components"
		do_components()

	-- vendor is last so it can trigger even if it were merely tagged
	group "vendor"
		do_vendor()
end, function(e)
	print(e)
	print(debug.traceback())

	os.exit(1)
end)
