# Operations reference

The connector exposes **27 customer-facing operations** (2 triggers + 25 actions), plus 3 internal helper operations that populate dynamic dropdowns automatically.

Base path is supplied by your connection (`https://{Host}{Base URL}`); the paths below are appended to it.

## Triggers

| Operation | Method | Path | Description |
|---|---|---|---|
| **Start Flow from Session Request without Timeout** (`StartFlowWithoutTimeout`) | POST | `/trigger/powerautomate/v1/trigger/ConsumePendingSessions` | Polls for new C TWO sessions and triggers the flow when a session is created for the selected task. Use this trigger when the automation doe… |
| **Start Flow from Session Request with Timeout** (`StartFlowWithTimeout`) | POST | `/trigger/powerautomate/v1/trigger/ConsumePendingSessionsWithRequiredTimeout` | Polls for new C TWO sessions and triggers the flow with a timeout constraint. Use this trigger when the automation must complete within a sp… |

## Session management

| Operation | Method | Path | Description |
|---|---|---|---|
| **Should Session Stop** (`IsStopRequested`) | GET | `/public/v2/sessions/isstoprequested/{sessionId}` | Checks whether C TWO has requested a graceful (soft) stop for the given session. Use this action inside loops to periodically check if the s… |
| **Add Log to Session** (`AddLogToSession`) | POST | `/powerautomate/v1/actions/log` | Writes a log entry to a C TWO session. Use this action to track progress, record decisions, or log diagnostic information during flow execut… |
| **Set Flow Execution State to Completed** (`SetSessionCompleted`) | POST | `/powerautomate/v1/actions/setsessioncompleted` | Marks a C TWO session as completed, signaling that the flow has finished its work successfully. Place this action at the end of your flow to… |
| **Set Flow Execution State to Failed** (`SetSessionFailed`) | POST | `/powerautomate/v1/actions/setsessionfailed` | Marks a C TWO session as failed, signaling that an error occurred during flow execution. Use this action in error-handling scopes to report … |
| **Set Session Timeout** (`SetTimeout`) | POST | `/powerautomate/v1/actions/settimeout` | Updates the timeout value for an active C TWO session. Use this action to extend or reduce the allowed execution time for a running session … |

## Universal Queue

| Operation | Method | Path | Description |
|---|---|---|---|
| **Remove Tags from Queue Item** (`RemoveItemTag`) | DELETE | `/universalqueues/v2/items/{queueItemId}/tag` | Removes one or more tags from a queue item. Use this action to update the categorization of work items during processing. |
| **Get Queue Items** (`GetItems`) | GET | `/universalqueues/v2/items` | Retrieves queue items based on specified filter criteria such as state, tags, dates, and queue names. Use this action to search for and moni… |
| **Get Queue Item Attachment** (`GetItemAttachment`) | GET | `/universalqueues/v2/items/{queueItemId}/attachment/{attachmentId}` | Retrieves a specific file attachment from a queue item as base64-encoded data. Use this action to download files that were attached to work … |
| **Get Queues** (`GetQueues`) | GET | `/universalqueues/v2/queues` | Retrieves universal queues based on filter criteria. Use this action to list available queues, check their configuration, or look up queue d… |
| **Lock Queue Item** (`LockItem`) | PATCH | `/universalqueues/v2/items/lock` | Locks a queue item to prevent other workers from processing it concurrently. Use this action before processing a work item to ensure exclusi… |
| **Defer Queue Item** (`DeferItem`) | PATCH | `/universalqueues/v2/items/{queueItemId}/defer` | Defers a queue item so it will not be processed until the specified date/time. Use this action when an item cannot be processed now but shou… |
| **Retry Queue Item** (`RetryItem`) | PATCH | `/universalqueues/v2/items/{queueItemId}/retry` | Retry a specific queue item, setting its data back to its original value and creating a new Attempt. |
| **Add Tags to Queue Item** (`AddItemTag`) | PATCH | `/universalqueues/v2/items/{queueItemId}/tag` | Adds one or more tags to a queue item for categorization and filtering. Tags help organize and search for work items across queues. |
| **Unlock Queue Item** (`UnlockItem`) | PATCH | `/universalqueues/v2/items/{queueItemId}/unlock` | Unlocks a previously locked queue item and returns it to its available state. Use this action when processing is interrupted and the item sh… |
| **Create Queue Item** (`CreateItem`) | POST | `/universalqueues/v2/items` | Creates a new work item in a specified universal queue. Use this action to add items for processing by digital workers, including data paylo… |
| **Set Queue Item Data** (`SetItemData`) | POST | `/universalqueues/v2/items/{queueItemId}/data` | Updates the data content of a queue item. Use this action to modify the payload of a work item during processing, for example to store inter… |
| **Add Log to Queue Item** (`AddItemLog`) | POST | `/universalqueues/v2/items/{queueItemId}/log` | Adds a log message to a queue item for audit trail and traceability. Use this action to record processing steps, warnings, or errors against… |
| **Set Queue Item State** (`SetItemState`) | POST | `/universalqueues/v2/items/{queueItemId}/setstate` | Changes the state of a queue item (e.g., from Pending to Completed, or to a custom state). Use this action to advance items through your wor… |
| **Create Queue Item State** (`CreateItemState`) | POST | `/universalqueues/v2/states` | Creates a new custom state within a specific queue. Custom states allow you to define workflow stages beyond the default states (Pending, Co… |

## Human-in-the-loop

| Operation | Method | Path | Description |
|---|---|---|---|
| **Get Forms** (`GetForms`) | GET | `/public/v2/robotToHumanHelpRequests` | Retrieves a list of robot interaction forms with optional filtering. Use this action to query pending human-in-the-loop requests, check thei… |
| **Get Form By Id** (`GetFormById`) | GET | `/public/v2/robotToHumanHelpRequests/{formId}` | Retrieves a specific robot interaction form by its unique identifier. Use this action to fetch the details, fields, and current status of a … |
| **Assign Form** (`AssignForm`) | PATCH | `/public/v2/robotToHumanHelpRequests/{formId}/assign` | Assigns a robot interaction form to a specific user, making them responsible for reviewing and completing the human-in-the-loop request. |
| **Complete Form** (`CompleteForm`) | PATCH | `/public/v2/robotToHumanHelpRequests/{formId}/complete` | Marks a robot interaction form as completed, signaling that the human user has provided the requested input and the digital worker can resum… |
| **Unassign Form** (`UnassignForm`) | PATCH | `/public/v2/robotToHumanHelpRequests/{formId}/unassign` | Removes the current user assignment from a robot interaction form, making it available for other users to claim. |
| **Create Form** (`CreateForm`) | POST | `/public/v2/robotToHumanHelpRequests/Create` | Creates a new robot interaction form that allows a digital worker to request human assistance. The form is presented to assigned users in th… |

## Internal (dropdown helpers — not called directly)

| Operation | Method | Path | Description |
|---|---|---|---|
| **GetExposedFlows** (`GetExposedFlows`) | GET | `/powerautomate/v1/actions/tasks` | Retrieves the list of C TWO tasks that are configured and ready to be triggered. This internal operation is used to populate dynamic dropdow… |
| **GetUsers** (`GetUsers`) | GET | `/public/v2/users` | Returns filtered users and service accounts. |
| **Get Tasks** (`GetTasks`) | GET | `/public/v2/workflowTasks` | Retrieves the list of tasks configured in the C TWO platform. This internal operation is used to populate dynamic dropdowns for task selecti… |
