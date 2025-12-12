// Global Configuration
const GRID_SIZE = 400; // 20x20
const START_NODE = 20;
const END_NODE = 379;
let walls = [];
let isPaused = false;
let animationId = null;
// const FIXED_WALLS = [
//     1, 2, 3, 4, 5, 25, 45, 65, 85, 
//     10, 11, 12, 13, 14, 15,        
//     55, 75, 95, 115, 135,
//     200, 201, 202, 203, 204, 224, 244,
//     300, 301, 302, 322, 342, 362,
//     150, 151, 152, 172, 192,
// ];


// UI Elements
const mazeDiv = document.getElementById('maze');
const btnSimulate = document.getElementById('btnSimulate');
const btnPause = document.getElementById('btnPause');
const btnContinue = document.getElementById('btnContinue');
const visitedCountLabel = document.getElementById('visitedCount');
const pathCountLabel = document.getElementById('pathCount');
const statusText = document.getElementById('statusText');

// 1. Initialize Grid
function initGrid() {
    mazeDiv.innerHTML = '';
    walls = [];
    
    for (let i = 0; i < GRID_SIZE; i++) {
        const div = document.createElement('div');
        div.classList.add('node');
        div.id = `node-${i}`;

        if (i === START_NODE) {
            div.classList.add('start');
            div.innerHTML = '<i class="fas fa-chevron-right"></i>';
        } else if (i === END_NODE) {
            div.classList.add('end');
            div.innerHTML = '<i class="fas fa-bullseye"></i>';
        } else if (Math.random() < 0.25) { 
            // 25% chance to be a wall (Random Map Generation)
            div.classList.add('wall');
            walls.push(i);
        }
        mazeDiv.appendChild(div);
    }
}

// function initGrid() {
//     mazeDiv.innerHTML = '';
    
//     walls = FIXED_WALLS; 
    
//     for (let i = 0; i < GRID_SIZE; i++) {
//         const div = document.createElement('div');
//         div.classList.add('node');
//         div.id = `node-${i}`;

//         if (i === START_NODE) {
//             div.classList.add('start');
//             div.innerHTML = '<i class="fas fa-chevron-right"></i>';
//         } else if (i === END_NODE) {
//             div.classList.add('end');
//             div.innerHTML = '<i class="fas fa-bullseye"></i>';
//         } 
//         else if (walls.includes(i)) { 
//             div.classList.add('wall');
//         }
        
//         mazeDiv.appendChild(div);
//     }
// }

// 2. Fetch API & Handle Logic
async function runSimulation() {
    // Reset UI
    resetVisualization();
    btnSimulate.disabled = true;
    btnPause.disabled = false;
    btnPause.innerHTML = '<i class="fas fa-pause"></i> Pause';
    statusText.innerText = "Searching...";
    statusText.className = "alert alert-primary border mb-0 mt-2 py-1 text-center small fw-bold";

    const algorithm = document.getElementById('algorithmSelect').value;

    let ApiUrl = '';
    // if(algorithm === 'bfs') ApiUrl = 'http://localhost:5000/solve/bfs';
    if(algorithm === 'bfs') ApiUrl = 'https://bgmrmybcpe.execute-api.us-east-1.amazonaws.com/solve/bfs';
    // else if(algorithm === 'dfs') ApiUrl = 'http://localhost:5000/solve/dfs' ;
    else if(algorithm === 'dfs') ApiUrl = 'https://bgmrmybcpe.execute-api.us-east-1.amazonaws.com/solve/dfs' ;
    // else if(algorithm === 'astar') ApiUrl = 'http://localhost:5000/solve/astar';
    else if(algorithm === 'astar') ApiUrl = 'https://bgmrmybcpe.execute-api.us-east-1.amazonaws.com/solve/astar';


    try {
        // Calling Python Flask API
        const response = await fetch(ApiUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                startNode: START_NODE,
                endNode: END_NODE,
                walls: walls,
                algorithm: algorithm
            })
        });

        

        const data = await response.json();

        console.log(data.visited)
        console.log(data.path)


        // Start Animation Loop
        animateAlgorithm(data.visited, data.path);

    } catch (error) {
        console.error("API Error:", error);
        statusText.innerText = "API Error! Check Console.";
        statusText.className = "alert alert-danger border mb-0 mt-2 py-1 text-center small fw-bold";
        btnSimulate.disabled = false;
    }
}

// 3. Animation Engine (Supports Pause/Continue)
let currentStep = 0;
let animationData = { visited: [], path: [] };

function animateAlgorithm(visitedNodes, pathNodes) {
    animationData.visited = visitedNodes;
    animationData.path = pathNodes;
    currentStep = 0;
    isPaused = false;
    
    processAnimationStep();
}

function processAnimationStep() {
    if (isPaused) return;

    // Phase 1: Animate Visited Nodes
    if (currentStep < animationData.visited.length) {
        const nodeId = animationData.visited[currentStep];
        const nodeDiv = document.getElementById(`node-${nodeId}`);
        
        if (nodeId !== START_NODE && nodeId !== END_NODE) {
            nodeDiv.classList.add('visited');
        }
        
        visitedCountLabel.innerText = currentStep + 1;
        currentStep++;
        
        // Control Speed here (20ms)
        animationId = setTimeout(processAnimationStep, 20); 
    } 
    // Phase 2: Animate Final Path
    else {
        // Calculate path step index (relative to path array)
        const pathIndex = currentStep - animationData.visited.length;
        
        if (pathIndex < animationData.path.length) {
            const nodeId = animationData.path[pathIndex];
            const nodeDiv = document.getElementById(`node-${nodeId}`);
            
            if (nodeId !== START_NODE && nodeId !== END_NODE) {
                nodeDiv.classList.add('path');
            }
            
            pathCountLabel.innerText = pathIndex + 1;
            currentStep++;
            animationId = setTimeout(processAnimationStep, 50); // Slower for path
        } else {
            finishSimulation();
        }
    }
}

function finishSimulation() {
    statusText.innerText = "Target Found!";
    statusText.className = "alert alert-success border mb-0 mt-2 py-1 text-center small fw-bold";
    btnSimulate.disabled = false;
    btnPause.disabled = true;
    btnContinue.disabled = true;
}

function resetVisualization() {
    clearTimeout(animationId);
    visitedCountLabel.innerText = 0;
    pathCountLabel.innerText = 0;
    
    document.querySelectorAll('.node').forEach(node => {
        node.classList.remove('visited', 'path');
    });
}

// 4. Event Listeners
btnSimulate.addEventListener('click', runSimulation);

btnPause.addEventListener('click', () => {
    isPaused = true;
    btnPause.disabled = true;
    btnContinue.disabled = false;
    statusText.innerText = "Paused";
});

btnContinue.addEventListener('click', () => {
    isPaused = false;
    btnPause.disabled = false;
    btnContinue.disabled = true;
    statusText.innerText = "Searching...";
    processAnimationStep();
});

// Init on load
window.onload = initGrid;