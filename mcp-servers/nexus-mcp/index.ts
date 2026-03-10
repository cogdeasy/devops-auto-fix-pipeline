import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const NEXUS_URL = process.env.NEXUS_URL || "http://localhost:8081";
const NEXUS_TOKEN = process.env.NEXUS_TOKEN || "";

async function nexusFetch(path: string): Promise<Response> {
  const url = `${NEXUS_URL}${path}`;
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${NEXUS_TOKEN}`,
      Accept: "application/json",
    },
  });
  return response;
}

const server = new Server(
  { name: "nexus-mcp", version: "1.0.0" },
  { capabilities: { tools: {}, resources: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "search_artifacts",
        description: "Search for artifacts in Nexus Repository Manager",
        inputSchema: {
          type: "object" as const,
          properties: {
            group: { type: "string", description: "Group ID to search for" },
            name: { type: "string", description: "Artifact name to search for" },
            version: { type: "string", description: "Version to search for" },
            repository: { type: "string", description: "Repository to search in" },
          },
        },
      },
      {
        name: "get_artifact_info",
        description: "Get detailed metadata for a specific artifact",
        inputSchema: {
          type: "object" as const,
          properties: {
            group: { type: "string", description: "Group ID" },
            name: { type: "string", description: "Artifact name" },
            version: { type: "string", description: "Artifact version" },
            repository: { type: "string", description: "Repository name" },
          },
          required: ["group", "name", "version"],
        },
      },
      {
        name: "check_dependency_vulnerabilities",
        description: "Check if a dependency has known vulnerability issues",
        inputSchema: {
          type: "object" as const,
          properties: {
            group: { type: "string", description: "Group ID" },
            name: { type: "string", description: "Artifact name" },
            version: { type: "string", description: "Artifact version" },
          },
          required: ["group", "name", "version"],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "search_artifacts") {
      const params = new URLSearchParams();
      if (args?.group) params.append("group", String(args.group));
      if (args?.name) params.append("name", String(args.name));
      if (args?.version) params.append("version", String(args.version));
      if (args?.repository) params.append("repository", String(args.repository));

      const response = await nexusFetch(`/service/rest/v1/search?${params.toString()}`);
      if (!response.ok) {
        return {
          content: [{ type: "text", text: `Nexus API error: ${response.status} ${response.statusText}` }],
          isError: true,
        };
      }

      const data = await response.json();
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }

    if (name === "get_artifact_info") {
      const group = String(args?.group);
      const artifactName = String(args?.name);
      const version = String(args?.version);
      const params = new URLSearchParams({ group, name: artifactName, version });
      if (args?.repository) params.append("repository", String(args.repository));

      const response = await nexusFetch(`/service/rest/v1/search?${params.toString()}`);
      if (!response.ok) {
        return {
          content: [{ type: "text", text: `Nexus API error: ${response.status} ${response.statusText}` }],
          isError: true,
        };
      }

      const data = await response.json();
      const component = data.items?.[0];
      if (!component) {
        return {
          content: [{ type: "text", text: `No artifact found for ${group}:${artifactName}:${version}` }],
          isError: true,
        };
      }

      return {
        content: [{ type: "text", text: JSON.stringify(component, null, 2) }],
      };
    }

    if (name === "check_dependency_vulnerabilities") {
      const group = String(args?.group);
      const artifactName = String(args?.name);
      const version = String(args?.version);

      const searchParams = new URLSearchParams({ group, name: artifactName, version });
      const searchResponse = await nexusFetch(`/service/rest/v1/search?${searchParams.toString()}`);

      let componentData = null;
      if (searchResponse.ok) {
        const searchData = await searchResponse.json();
        componentData = searchData.items?.[0] || null;
      }

      let vulnerabilities = null;
      try {
        const vulnResponse = await nexusFetch(
          `/service/rest/v1/vulnerabilities/${encodeURIComponent(group)}/${encodeURIComponent(artifactName)}/${encodeURIComponent(version)}`
        );
        if (vulnResponse.ok) {
          vulnerabilities = await vulnResponse.json();
        }
      } catch (_) {
        vulnerabilities = null;
      }

      const result = {
        component: componentData
          ? { group, name: artifactName, version, found: true }
          : { group, name: artifactName, version, found: false },
        vulnerabilities: vulnerabilities || { status: "no_data", message: "No vulnerability data available" },
      };

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }

    return {
      content: [{ type: "text", text: `Unknown tool: ${name}` }],
      isError: true,
    };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error instanceof Error ? error.message : String(error)}` }],
      isError: true,
    };
  }
});

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: "nexus://repositories",
        name: "Nexus Repositories",
        description: "List all repositories in Nexus Repository Manager",
        mimeType: "application/json",
      },
    ],
    resourceTemplates: [
      {
        uriTemplate: "nexus://artifact/{group}/{name}/{version}",
        name: "Artifact Info",
        description: "Get artifact information by group, name, and version",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  if (uri === "nexus://repositories") {
    try {
      const response = await nexusFetch("/service/rest/v1/repositories");
      if (!response.ok) {
        throw new Error(`Nexus API error: ${response.status} ${response.statusText}`);
      }
      const data = await response.json();
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    } catch (error) {
      throw new Error(`Failed to fetch repositories: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  const artifactMatch = uri.match(/^nexus:\/\/artifact\/([^/]+)\/([^/]+)\/([^/]+)$/);
  if (artifactMatch) {
    const [, group, name, version] = artifactMatch;
    try {
      const params = new URLSearchParams({
        group: decodeURIComponent(group),
        name: decodeURIComponent(name),
        version: decodeURIComponent(version),
      });
      const response = await nexusFetch(`/service/rest/v1/search?${params.toString()}`);
      if (!response.ok) {
        throw new Error(`Nexus API error: ${response.status} ${response.statusText}`);
      }
      const data = await response.json();
      const component = data.items?.[0];
      if (!component) {
        throw new Error(`Artifact not found: ${group}:${name}:${version}`);
      }
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: JSON.stringify(component, null, 2),
          },
        ],
      };
    } catch (error) {
      throw new Error(`Failed to fetch artifact: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  throw new Error(`Unknown resource: ${uri}`);
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  process.stderr.write(`Fatal error: ${error}\n`);
  process.exit(1);
});
