import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const JENKINS_URL = process.env.JENKINS_URL || "http://localhost:8080";
const JENKINS_USER = process.env.JENKINS_USER || "";
const JENKINS_TOKEN = process.env.JENKINS_TOKEN || "";

async function jenkinsFetch(path: string, method: string = "GET"): Promise<Response> {
  const url = `${JENKINS_URL}${path}`;
  const credentials = Buffer.from(`${JENKINS_USER}:${JENKINS_TOKEN}`).toString("base64");
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Basic ${credentials}`,
    },
  });
  return response;
}

const server = new Server(
  { name: "jenkins-mcp", version: "1.0.0" },
  { capabilities: { tools: {}, resources: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "get_failed_builds",
        description: "List recent failed builds for a Jenkins job",
        inputSchema: {
          type: "object" as const,
          properties: {
            jobName: { type: "string", description: "The Jenkins job name" },
            limit: { type: "number", description: "Maximum number of builds to check", default: 10 },
          },
          required: ["jobName"],
        },
      },
      {
        name: "get_build_log",
        description: "Fetch console output for a specific build",
        inputSchema: {
          type: "object" as const,
          properties: {
            jobName: { type: "string", description: "The Jenkins job name" },
            buildNumber: { type: "number", description: "The build number" },
          },
          required: ["jobName", "buildNumber"],
        },
      },
      {
        name: "trigger_build",
        description: "Trigger a new build for a Jenkins job",
        inputSchema: {
          type: "object" as const,
          properties: {
            jobName: { type: "string", description: "The Jenkins job name" },
            parameters: {
              type: "object",
              description: "Build parameters as key-value pairs",
              additionalProperties: { type: "string" },
            },
          },
          required: ["jobName"],
        },
      },
      {
        name: "get_build_status",
        description: "Check build status and result",
        inputSchema: {
          type: "object" as const,
          properties: {
            jobName: { type: "string", description: "The Jenkins job name" },
            buildNumber: { type: "number", description: "The build number" },
          },
          required: ["jobName", "buildNumber"],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "get_failed_builds": {
        const jobName = args?.jobName as string;
        const limit = (args?.limit as number) || 10;
        const response = await jenkinsFetch(
          `/job/${jobName}/api/json?tree=builds[number,result,timestamp,duration,url]{0,${limit}}`
        );
        if (!response.ok) {
          return {
            content: [{ type: "text", text: `Failed to fetch builds: ${response.statusText}` }],
            isError: true,
          };
        }
        const data = await response.json() as { builds: Array<{ number: number; result: string; timestamp: number; duration: number; url: string }> };
        const failedBuilds = (data.builds || []).filter(
          (build: { result: string }) => build.result === "FAILURE"
        );
        return {
          content: [{ type: "text", text: JSON.stringify(failedBuilds, null, 2) }],
        };
      }

      case "get_build_log": {
        const jobName = args?.jobName as string;
        const buildNumber = args?.buildNumber as number;
        const response = await jenkinsFetch(`/job/${jobName}/${buildNumber}/consoleText`);
        if (!response.ok) {
          return {
            content: [{ type: "text", text: `Failed to fetch build log: ${response.statusText}` }],
            isError: true,
          };
        }
        const text = await response.text();
        return {
          content: [{ type: "text", text }],
        };
      }

      case "trigger_build": {
        const jobName = args?.jobName as string;
        const parameters = args?.parameters as Record<string, string> | undefined;
        let path: string;
        if (parameters && Object.keys(parameters).length > 0) {
          const params = new URLSearchParams(parameters).toString();
          path = `/job/${jobName}/buildWithParameters?${params}`;
        } else {
          path = `/job/${jobName}/build`;
        }
        const response = await jenkinsFetch(path, "POST");
        if (!response.ok) {
          return {
            content: [{ type: "text", text: `Failed to trigger build: ${response.statusText}` }],
            isError: true,
          };
        }
        return {
          content: [{ type: "text", text: `Build triggered successfully for ${jobName}` }],
        };
      }

      case "get_build_status": {
        const jobName = args?.jobName as string;
        const buildNumber = args?.buildNumber as number;
        const response = await jenkinsFetch(`/job/${jobName}/${buildNumber}/api/json`);
        if (!response.ok) {
          return {
            content: [{ type: "text", text: `Failed to fetch build status: ${response.statusText}` }],
            isError: true,
          };
        }
        const data = await response.json();
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
        };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
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
        uri: "jenkins://jobs",
        name: "Jenkins Jobs",
        description: "List of all Jenkins jobs",
        mimeType: "application/json",
      },
    ],
    resourceTemplates: [
      {
        uriTemplate: "jenkins://build/{jobName}/{buildNumber}",
        name: "Jenkins Build Details",
        description: "Details for a specific Jenkins build",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  try {
    if (uri === "jenkins://jobs") {
      const response = await jenkinsFetch("/api/json?tree=jobs[name,url,color]");
      if (!response.ok) {
        throw new Error(`Failed to fetch jobs: ${response.statusText}`);
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
    }

    const buildMatch = uri.match(/^jenkins:\/\/build\/([^/]+)\/(\d+)$/);
    if (buildMatch) {
      const jobName = buildMatch[1];
      const buildNumber = buildMatch[2];
      const response = await jenkinsFetch(`/job/${jobName}/${buildNumber}/api/json`);
      if (!response.ok) {
        throw new Error(`Failed to fetch build details: ${response.statusText}`);
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
    }

    throw new Error(`Unknown resource: ${uri}`);
  } catch (error) {
    throw new Error(`Resource error: ${error instanceof Error ? error.message : String(error)}`);
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
