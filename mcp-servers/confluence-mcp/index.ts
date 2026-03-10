import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListResourceTemplatesRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const CONFLUENCE_URL = process.env.CONFLUENCE_URL!;
const CONFLUENCE_USER = process.env.CONFLUENCE_USER!;
const CONFLUENCE_TOKEN = process.env.CONFLUENCE_TOKEN!;

async function confluenceFetch(path: string) {
  const url = `${CONFLUENCE_URL}${path}`;
  const auth = Buffer.from(`${CONFLUENCE_USER}:${CONFLUENCE_TOKEN}`).toString("base64");
  const response = await fetch(url, {
    headers: {
      Authorization: `Basic ${auth}`,
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`Confluence API error: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

const server = new Server(
  { name: "confluence-mcp", version: "1.0.0" },
  { capabilities: { tools: {}, resources: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "search_pages",
        description: "Search Confluence for pages matching a query using CQL",
        inputSchema: {
          type: "object" as const,
          properties: {
            query: { type: "string", description: "CQL search query" },
            limit: { type: "number", description: "Maximum number of results", default: 10 },
          },
          required: ["query"],
        },
      },
      {
        name: "get_page_content",
        description: "Fetch a specific Confluence page's content",
        inputSchema: {
          type: "object" as const,
          properties: {
            pageId: { type: "string", description: "The Confluence page ID" },
          },
          required: ["pageId"],
        },
      },
      {
        name: "search_known_issues",
        description: "Search for known issues matching error patterns in a specific space",
        inputSchema: {
          type: "object" as const,
          properties: {
            errorPattern: { type: "string", description: "Error pattern to search for" },
            space: { type: "string", description: "Confluence space key to search in" },
          },
          required: ["errorPattern"],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "search_pages") {
      const query = args?.query as string;
      const limit = (args?.limit as number) || 10;
      const data = await confluenceFetch(
        `/rest/api/content/search?cql=${encodeURIComponent(query)}&limit=${limit}&expand=space,version`
      );
      return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
    }

    if (name === "get_page_content") {
      const pageId = args?.pageId as string;
      const data = await confluenceFetch(
        `/rest/api/content/${pageId}?expand=body.storage,version,space`
      );
      return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
    }

    if (name === "search_known_issues") {
      const errorPattern = args?.errorPattern as string;
      const space = args?.space as string | undefined;
      let cql = `type=page AND label="known-issue" AND text~"${errorPattern}"`;
      if (space) {
        cql += ` AND space="${space}"`;
      }
      const data = await confluenceFetch(
        `/rest/api/content/search?cql=${encodeURIComponent(cql)}&limit=10&expand=space,version`
      );
      return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
    }

    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
  }
});

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: "confluence://spaces",
        name: "Confluence Spaces",
        description: "List all Confluence spaces",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ListResourceTemplatesRequestSchema, async () => {
  return {
    resourceTemplates: [
      {
        uriTemplate: "confluence://page/{pageId}",
        name: "Confluence Page",
        description: "Get content of a specific Confluence page",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  try {
    if (uri === "confluence://spaces") {
      const data = await confluenceFetch("/rest/api/space?limit=100");
      return {
        contents: [
          {
            uri: "confluence://spaces",
            mimeType: "application/json",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    }

    const pageMatch = uri.match(/^confluence:\/\/page\/(.+)$/);
    if (pageMatch) {
      const pageId = pageMatch[1];
      const data = await confluenceFetch(
        `/rest/api/content/${pageId}?expand=body.storage,version,space`
      );
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    }

    throw new Error(`Unknown resource: ${uri}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to read resource ${uri}: ${message}`);
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
