import json
import heapq
from maze_modules.modules import get_neighbors, reconstruct_path ,heuristic


ROWS = 20
COLS = 20

def lambda_handler(event ,context) :
    
    if 'body' in event and isinstance(event['body'], str):
        event = json.loads(event['body'])

    start_node = event.get('startNode')
    end_node = event.get('endNode')
    walls = set(event.get('walls', []))

    open_set = []
    heapq.heappush(open_set, (0, start_node))
    
    parent_map = {start_node: None}
    
    g_score = {node: float('inf') for node in range(ROWS * COLS)}
    g_score[start_node] = 0
    
    visited_order = []
    visited_set = set() 

    found = False

    while open_set:
        current_f, current = heapq.heappop(open_set)
        visited_order.append(current)

        if current == end_node:
            found = True
            break
        
        visited_set.add(current)

        for neighbor in get_neighbors(current, walls):
            if neighbor in visited_set:
                continue
                
            tentative_g_score = g_score[current] + 1 

            if tentative_g_score < g_score[neighbor]:
                parent_map[neighbor] = current
                g_score[neighbor] = tentative_g_score
                f_score = tentative_g_score + heuristic(neighbor, end_node)
                heapq.heappush(open_set, (f_score, neighbor))

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
