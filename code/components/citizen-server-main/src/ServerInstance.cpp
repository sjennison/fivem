/*
 * This file is part of the CitizenFX project - http://citizen.re/
 *
 * See LICENSE and MENTIONS in the root of the source tree for information
 * regarding licensing.
 */

#include "StdInc.h"
#include <ServerInstance.h>

#include <OptionParser.h>

#include <boost/property_tree/xml_parser.hpp>

#include <boost/filesystem.hpp>

#include <ComponentLoader.h>

#include <CoreConsole.h>

#include <VFSManager.h>

namespace fx
{
	ServerInstance::ServerInstance()
		: m_shouldTerminate(false)
	{
		// create a console context
		fwRefContainer<console::Context> consoleContext;
		console::CreateContext(console::GetDefaultContext(), &consoleContext);

		SetComponent(consoleContext);

		m_execCommand = AddCommand("exec", [=](const std::string& path) {
			fwRefContainer<vfs::Stream> stream = vfs::OpenRead(path);

			if (!stream.GetRef())
			{
				console::Printf("cmd", "No such config file: %s\n", path.c_str());
				return;
			}

			std::vector<uint8_t> data = stream->ReadToEnd();
			data.push_back('\n'); // add a newline at the end

			auto consoleCtx = GetComponent<console::Context>();

			consoleCtx->AddToBuffer(std::string(reinterpret_cast<char*>(&data[0]), data.size()));
			consoleCtx->ExecuteBuffer();
		});

		SetComponent(new fx::OptionParser());
	}

	bool ServerInstance::SetArguments(const std::string& arguments)
	{
		auto optionParser = GetComponent<OptionParser>();
		
		return optionParser->ParseArgumentString(arguments);
	}

	void ServerInstance::Run()
	{
		// initialize the server configuration
		{
			auto optionParser = GetComponent<OptionParser>();
			auto consoleCtx = GetComponent<console::Context>();

			for (const auto& set : optionParser->GetSetList())
			{
				consoleCtx->ExecuteSingleCommand(ProgramArguments{ "set", set.first, set.second });
			}

			boost::filesystem::path rootPath;

			try
			{
				rootPath = boost::filesystem::canonical(".");

				m_rootPath = rootPath.string();
			}
			catch (std::exception& error)
			{
			}

			// invoke target events
			OnServerCreate(this);

			for (const auto& bit : optionParser->GetArguments())
			{
				consoleCtx->ExecuteSingleCommand(bit);
			}

			OnInitialConfiguration();
		}

		// tasks should be running in background threads; we'll just wait until someone wants to get rid of us
		while (!m_shouldTerminate)
		{
			std::this_thread::sleep_for(std::chrono::seconds(1));
		}
	}
}

class ServerMain
{
	virtual void Run(fwRefContainer<Component> component)
	{
		// run the server's main routine
		fwRefContainer<RunnableComponent> runnableServer = dynamic_cast<RunnableComponent*>(component.GetRef());

		if (runnableServer.GetRef() != nullptr)
		{
			runnableServer->Run();
		}
		else
		{
			trace("citizen:server:main component does not implement RunnableComponent. Exiting.\n");
		}
	}
};

static ServerMain g_main;

DECLARE_INSTANCE_TYPE(ServerMain);

static InitFunction initFunction([]()
{
	Instance<ServerMain>::Set(&g_main);
});
