### **Functional Specification: Reinforcement Learning (RL) Integration Hooks**

*   **Document Version:** 1.0
*   **Status:** For Implementation
*   **Feature:** PRD-F2 (Integrated Learning Mechanisms)

**1. Introduction & Goal**

The primary goal of this feature is to create a feedback mechanism that allows Agrama to learn from an agent's successes and failures. By enabling an external Reinforcement Learning (RL) system to assign and update weights on memory elements (nodes and edges), we can transform Agrama from a passive memory store into an active, adaptive knowledge base. This will allow the agent to refine its strategies, prioritize effective solutions, and improve its problem-solving capabilities over time.

**2. Core Functional Requirements**

**2.1. Data Model Extension**

The core `Node` and `Edge` data structures within `database.zig` must be extended to support learned weights.

*   **FR2.1.1 - Weighted Nodes:** The `Node` struct must include a new optional field: `weight: ?f32`. This allows for storing scores on entities like `CodeUnit` or `ErrorSolutionPair`.
*   **FR2.1.2 - Weighted Edges:** The `Edge` struct must include a new optional field: `weight: ?f32`. This is critical for scoring relationships, such as the effectiveness of a `solved_by` edge or the relevance of a `similar_to` link.
*   **FR2.1.3 - Performance:** The addition of these fields should not introduce significant overhead for nodes and edges that do not have a weight. The implementation should be memory-efficient.

**2.2. API: MCP Tool for Weight Updates**

A new MCP (Model Context Protocol) tool must be created to allow a trusted external service (the RL Evaluator) to modify these weights.

*   **FR2.2.1 - Tool Definition:**
    *   **Name:** `agrama/updateEntityWeight`
    *   **Description:** "Updates the learned numerical weight of a specific node or edge in the graph. Intended for use by RL or other evaluation systems."
*   **FR2.2.2 - Tool Arguments:**
    *   `entity_id` (string, required): The UUID of the node or edge to be updated.
    *   `entity_type` (string, required): The type of the entity. Must be either `"NODE"` or `"EDGE"`.
    *   `weight` (float, required): The new floating-point value for the weight.
*   **FR2.2.3 - Tool Result:**
    *   On success, returns a JSON object confirming the update:
        ```json
        {
          "status": "success",
          "entity_id": "uuid-of-updated-entity",
          "new_weight": 1.5
        }
        ```
*   **FR2.2.4 - Example JSON-RPC Call:**
    ```json
    {
      "jsonrpc": "2.0",
      "id": 123,
      "method": "tools/call",
      "params": {
        "name": "agrama/updateEntityWeight",
        "arguments": {
          "entity_id": "edge-uuid-solution-to-error",
          "entity_type": "EDGE",
          "weight": 0.85
        }
      }
    }
    ```

**2.3. API: Integrating Weights into Retrieval**

Existing query tools must be enhanced to expose these weights, making them useful for the agent's cognitive architecture.

*   **FR2.3.1 - Enhanced Query Results:** The responses for existing graph traversal and search tools (e.g., `get_neighbors`, `find_similar_nodes`) must be modified to optionally include the `weight` field for any returned nodes or edges that have one.
*   **FR2.3.2 - Query Filtering/Sorting (Optional V2):** For future consideration, query arguments could be extended to allow sorting or filtering based on weight (e.g., `sort_by: "weight_desc"`).

**3. Use Case Workflow: Learning from a Successful Debugging Session**

1.  **Encounter Error:** An agent encounters a "null pointer exception" in `auth.zig`.
2.  **Query Agrama:** The agent queries Agrama for `ErrorSolutionPair` nodes semantically similar to the error message.
3.  **Receive Solutions:** Agrama returns two potential solutions. Solution A has a `solved_by` edge with a weight of `0.4`, and Solution B's edge has a weight of `0.7`.
4.  **Attempt Solution:** Based on the higher weight, the agent's logic prioritizes and attempts Solution B, which successfully resolves the error.
5.  **Provide Feedback:** The agent (or a monitoring component) confirms the success to an external RL Evaluator service.
6.  **Update Weight:** The RL Evaluator calls the `agrama/updateEntityWeight` tool, increasing the weight of the `solved_by` edge associated with Solution B to `0.9`.
7.  **Future Benefit:** The next time a similar error occurs, Solution B will be retrieved with an even higher priority, demonstrating learned behavior.

---

### **Functional Specification: Memory Compaction & Summarization**

*   **Document Version:** 1.0
*   **Status:** For Implementation
*   **Feature:** PRD-F3 (Memory Compaction/Summarization)

**1. Introduction & Goal**

The goal of this feature is to prevent the agent's memory from becoming cluttered with low-value, high-volume interaction data. By providing a mechanism to summarize a series of interactions into a single, high-level "memory," we improve the signal-to-noise ratio, ensure long-term performance and scalability, and create a hierarchical memory structure. This process will be asynchronous and leverage an external LLM service for the actual summarization task.

**2. Core Functional Requirements**

**2.1. Data Model Extension**

New node and edge types are required to represent summarized memories.

*   **FR2.1.1 - Summary Node:** A new node type named `SummaryNode` must be added.
    *   **Attributes:**
        *   `summary_content` (string): The LLM-generated high-level summary.
        *   `original_node_ids` (array of strings): A list of UUIDs of the `Interaction` nodes that were summarized.
        *   `generating_model` (string, optional): The name of the LLM that created the summary (e.g., "claude-3.5-sonnet-20240620").
*   **FR2.1.2 - Archived Status:** Nodes that have been summarized should be marked with a status (e.g., `status: "ARCHIVED"`). Archived nodes must be excluded from standard search and traversal queries by default, but remain retrievable by direct ID lookup for auditing.
*   **FR2.1.3 - Summarization Edge:** A new edge type `summarized_by` should be created to link each archived node to its new `SummaryNode`.

**2.2. API: Triggering the Compaction Process**

An MCP tool is needed for the agent to initiate the summarization process.

*   **FR2.2.1 - Tool Definition:**
    *   **Name:** `agrama/triggerCompaction`
    *   **Description:** "Initiates an asynchronous memory compaction process for a given set of nodes. Agrama will delegate the summarization task to a configured external service."
*   **FR2.2.2 - Tool Arguments:**
    *   `node_ids` (array of strings, required): The list of node UUIDs to be summarized (e.g., all `Interaction` nodes from a completed task).
*   **FR2.2.3 - Tool Result:**
    *   This is an asynchronous operation. The tool should immediately return a confirmation that the process has been initiated:
        ```json
        {
          "status": "success",
          "message": "Compaction process initiated for N nodes.",
          "job_id": "compaction-job-uuid"
        }
        ```

**2.3. API: Ingesting the Completed Summary**

A secure, internal-facing API endpoint (or a privileged MCP tool) is required for the external summarizer service to submit its result back to Agrama.

*   **FR2.3.1 - Tool Definition:**
    *   **Name:** `agrama/createSummaryNode`
    *   **Description:** "Creates a new SummaryNode and archives the original nodes. To be called by the trusted memory summarization service."
*   **FR2.3.2 - Tool Arguments:**
    *   `summary_content` (string, required): The text of the summary.
    *   `original_node_ids` (array of strings, required): The list of UUIDs that were summarized.
    *   `generating_model` (string, optional): The name of the LLM used.
*   **FR2.3.3 - Tool Result:**
    *   On success, returns the UUID of the newly created `SummaryNode`:
        ```json
        {
          "status": "success",
          "summary_node_id": "new-summary-node-uuid"
        }
        ```

**3. High-Level Asynchronous Workflow**

1.  **Agent Trigger:** The AI Agent completes a task and calls `agrama/triggerCompaction` with the IDs of all `Interaction` nodes from that task.
2.  **Agrama Acknowledges:** Agrama immediately responds with a success message and a job ID.
3.  **Agrama Delegates (Async):** In the background, Agrama retrieves the content of the specified nodes. It then makes an HTTP POST request to a pre-configured external endpoint (e.g., `http://summarizer-service/summarize`), sending the collected data.
4.  **External Service Summarizes:** The external service (e.g., `tools/conversation_processor.py` running as a web service) receives the data, formats it into a prompt, and gets a summary from an LLM.
5.  **Service Reports Back:** The external service calls the `agrama/createSummaryNode` MCP tool with the final summary and the list of original node IDs.
6.  **Agrama Finalizes:** Agrama:
    a. Creates the new `SummaryNode`.
    b. For each original node, it sets its status to `ARCHIVED`.
    c. Creates a `summarized_by` edge from each original node to the new `SummaryNode`.

**4. Non-Functional Requirements**

*   **NFR4.1 - Asynchronicity:** The `triggerCompaction` tool must be non-blocking and return in under 50ms.
*   **NFR4.2 - Configurability:** The URL of the external summarization service must be configurable in Agrama's settings.
*   **NFR4.3 - Error Handling:** If the external service fails to respond or returns an error, Agrama must log the failure and ensure the original nodes are *not* archived.
*   **NFR4.4 - Security:** The `agrama/createSummaryNode` tool/endpoint must be protected and only accessible by trusted internal services.