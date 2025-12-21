import json
from maze_modules.modules import get_neighbors, reconstruct_path


def lambda_handler(event ,context) :
    
    if 'body' in event and isinstance(event['body'], str):
        event = json.loads(event['body'])
    
    start_node = event.get('startNode')
    end_node = event.get('endNode')
    walls = set(event.get('walls', []))

    stack = [start_node] 
    visited_order = []
    visited_set = {start_node}
    parent_map = {start_node: None}
    
    found = False

    while stack:
        current = stack.pop()
        visited_order.append(current)

        if current == end_node:
            found = True
            break

        neighbors = get_neighbors(current, walls)
        
        for neighbor in neighbors:
            if neighbor not in visited_set:
                visited_set.add(neighbor)
                parent_map[neighbor] = current
                stack.append(neighbor)

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