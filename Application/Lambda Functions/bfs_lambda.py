import json
from collections import deque
from maze_modules.modules import get_neighbors, reconstruct_path

def lambda_handler(event, context):

    if 'body' in event and isinstance(event['body'], str):
        event = json.loads(event['body'])

    start_node = event.get('startNode')
    end_node = event.get('endNode')
    walls = set(event.get('walls', []))

    queue = deque([start_node])
    visited_order = []
    visited_set = {start_node}
    parent_map = {start_node: None}
    
    found = False

    while queue:
        current = queue.popleft()
        visited_order.append(current)

        if current == end_node:
            found = True
            break

        for neighbor in get_neighbors(current, walls):
            if neighbor not in visited_set:
                visited_set.add(neighbor)
                parent_map[neighbor] = current
                queue.append(neighbor)

    response_body = {
        "visited": visited_order,
        "path": reconstruct_path(parent_map, end_node) if found else [],
        "status": "Found" if found else "Not Found"
    }
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(response_body)
    }

    