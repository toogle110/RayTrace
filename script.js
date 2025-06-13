import { spheres, boxes, pyramids, sceneBounds } from './senceObject.js';
import { OctreeNode } from './Octree.js';
import { Encoder } from './encoder.js';

// 获取 canvas 元素并获取 WebGL 上下文
const canvas = document.getElementById("glcanvas");
const gl = canvas.getContext("webgl2");

console.log(gl);     // 是否为 null

// 设置画布尺寸为全屏
canvas.width = window.innerWidth;
canvas.height = window.innerHeight;

// 定义初始相机位置（比如z=2）
let cameraRadius = 10;
let camereTheta = 90;
let cameraPhi = 90;

let lightRadius = 9;
let lightTheta = 90;
let lightPhi = -90;

const root = new OctreeNode(sceneBounds);

const maxSpheres = 10;

// 球
const sphereCenters = new Float32Array(maxSpheres * 3);
const sphereRadii = new Float32Array(maxSpheres);
const sphereColors = new Float32Array(maxSpheres * 3);
const sphereReflectivities = new Float32Array(maxSpheres);
const sphereType = new Int32Array(maxSpheres);
const sphereIor = new Float32Array(maxSpheres);

// 立方体
const boxCenters = new Float32Array(maxSpheres * 3);  // center
const boxSizes = new Float32Array(maxSpheres * 3);    // half-size (extent)
const boxColors = new Float32Array(maxSpheres * 3);
const boxReflectivities = new Float32Array(maxSpheres);
const boxType = new Int16Array(maxSpheres);
const boxIor = new Float32Array(maxSpheres);

// 棱锥
const pyramidCenters = new Float32Array(maxSpheres * 3);
const pyramidHeights = new Float32Array(maxSpheres);
const pyramidBases = new Float32Array(maxSpheres);  // base square width
const pyramidColors = new Float32Array(maxSpheres * 3);
const pyramidReflectivities = new Float32Array(maxSpheres);
const pyramidType = new Int16Array(maxSpheres);
const pyramidIor = new Float32Array(maxSpheres);


loadObjectData();

// 启动初始化
init();

/**
 * 初始化 WebGL 渲染流程
 */
async function init() {
    // 加载着色器源码
    const [vsSource, fsSource] = await Promise.all([
        loadShaderSource("vertex.glsl"),
        loadShaderSource("fragment.glsl")
    ]);

    // 创建 shader 程序
    const program = createProgram(gl, vsSource, fsSource);
    if (!program) return;

    gl.useProgram(program);

    // === 设置顶点缓冲 ===
    const vertices = new Float32Array([
        -1, -1,  1, -1, -1,  1,
        -1,  1,  1, -1,  1,  1
    ]);

    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

    const aPosition = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(aPosition);
    gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 0, 0);

    // 获取 uniform 位置

    const uCameraPos = gl.getUniformLocation(program, "u_cameraPos");
    const uCameraUp = gl.getUniformLocation(program, 'u_cameraUp');
    const uLightPos = gl.getUniformLocation(program, 'u_lightPosition');

    const uResolution = gl.getUniformLocation(program, "u_resolution");
    const uTime = gl.getUniformLocation(program, "u_time");

    connectObjectToShader(program);

    // === 渲染循环 ===
    function render(time) {
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.clear(gl.COLOR_BUFFER_BIT);

        
        gl.uniform3fv(uCameraPos, getCameraPos(cameraRadius, camereTheta, cameraPhi));
        gl.uniform3fv(uLightPos, getCameraPos(lightRadius, lightTheta, lightPhi));
        gl.uniform3fv(uCameraUp, getCameraPos(cameraRadius, camereTheta, cameraPhi - 90));
        gl.uniform2f(uResolution, canvas.width, canvas.height);
        gl.uniform1f(uTime, time * 0.001);

        gl.drawArrays(gl.TRIANGLES, 0, 6);

        requestAnimationFrame(render);
    }

    requestAnimationFrame(render);
}


function loadObjectData(){

    let index = 0;
    // 球体
    spheres.forEach((s, i) => {
        sphereCenters.set(s.center, i * 3);
        sphereRadii[i] = s.radius;
        sphereColors.set(s.color, i * 3);
        sphereReflectivities[i] = s.reflectivity;
        sphereType[i] = s.type;
        sphereIor[i] = s.ior;
        s.index = index;
        index++;
        root.insert(s);
    });


    // 立方体
    boxes.forEach((b, i) => {
        boxCenters.set(b.center, i * 3);
        boxSizes.set(b.size, i * 3);
        boxColors.set(b.color, i * 3);
        boxReflectivities[i] = b.reflectivity;
        boxType[i] = b.type;
        boxIor[i] = b.ior;
        b.index = index;
        index++;
        root.insert(b);
    });


    // 棱锥
    pyramids.forEach((p, i) => {
        pyramidCenters.set(p.center, i * 3);
        pyramidHeights[i] = p.height;
        pyramidBases[i] = p.base;
        pyramidColors.set(p.color, i * 3);
        pyramidReflectivities[i] = p.reflectivity;
        pyramidType[i] = p.type;
        pyramidIor[i] = p.ior;

        p.index = index;
        index++;
        root.insert(p);
    });
}


function connectObjectToShader(program){
    connectSphereToShader(program);

    connectBoxToShader(program);

    connectPyramidToShader(program);

    connectOctreeToShader(program);
}

function connectSphereToShader(program){
    const uSphereCenters = gl.getUniformLocation(program, 'u_sphereCenters');
    const uSphereRadii = gl.getUniformLocation(program, 'u_sphereRadii');
    const uSphereCount = gl.getUniformLocation(program, 'u_sphereCount');
    const uSphereColors = gl.getUniformLocation(program, "u_sphereColors");
    const uSphereReflectivitys = gl.getUniformLocation(program, "u_sphereReflectivitys");
    const uSphereType = gl.getUniformLocation(program, "u_sphereType");
    const uSphereIor = gl.getUniformLocation(program, "u_sphereIor");

    gl.uniform3fv(uSphereCenters, sphereCenters);
    gl.uniform1fv(uSphereRadii, sphereRadii);
    gl.uniform1i(uSphereCount, spheres.length);
    gl.uniform3fv(uSphereColors, sphereColors);
    gl.uniform1fv(uSphereReflectivitys, sphereReflectivities);
    gl.uniform1iv(uSphereType, sphereType);
    gl.uniform1fv(uSphereIor, sphereIor);
}

function connectBoxToShader(program){
    const uBoxCenters = gl.getUniformLocation(program, 'u_boxCenters');
    const uBoxSizes = gl.getUniformLocation(program, 'u_boxSizes');
    const uBoxCount = gl.getUniformLocation(program, 'u_boxCount');
    const uBoxColors = gl.getUniformLocation(program, 'u_boxColors');
    const uBoxReflectivitys = gl.getUniformLocation(program, "u_boxReflectivitys");
    const uBoxType = gl.getUniformLocation(program, "u_boxType");
    const uBoxIor = gl.getUniformLocation(program, "u_boxIor");

    gl.uniform3fv(uBoxCenters, boxCenters);
    gl.uniform3fv(uBoxSizes, boxSizes);
    gl.uniform1i(uBoxCount, boxes.length);
    gl.uniform3fv(uBoxColors, boxColors);
    gl.uniform1fv(uBoxReflectivitys, boxReflectivities);
    gl.uniform1iv(uBoxType, boxType);
    gl.uniform1fv(uBoxIor, boxIor);
}

function connectPyramidToShader(program){
    const uPyramidCenters = gl.getUniformLocation(program, 'u_pyramidCenters');
    const uPyramidHeights = gl.getUniformLocation(program, 'u_pyramidHeights');
    const uPyramidBases = gl.getUniformLocation(program, 'u_pyramidBases');
    const uPyramidCount = gl.getUniformLocation(program, 'u_pyramidCount');
    const uPyramidColors = gl.getUniformLocation(program, 'u_pyramidColors');
    const uPyramidReflectivitys = gl.getUniformLocation(program, "u_pyramidReflectivitys");
    const uPyramidType = gl.getUniformLocation(program, "u_pyramidType");
    const uPyramidIor = gl.getUniformLocation(program, "u_pyramidIor");

    gl.uniform3fv(uPyramidCenters, pyramidCenters);
    gl.uniform1fv(uPyramidHeights, pyramidHeights);
    gl.uniform1fv(uPyramidBases, pyramidBases);
    gl.uniform1i(uPyramidCount, pyramids.length);
    gl.uniform3fv(uPyramidColors, pyramidColors);
    gl.uniform1fv(uPyramidReflectivitys, pyramidReflectivities);
    gl.uniform1iv(uPyramidType, pyramidType);
    gl.uniform1fv(uPyramidIor, pyramidIor);
}

function connectOctreeToShader(program){

    const {
        nodeList,
        nodeObjectIndices,
        nodeObjectRanges
    } = root.flattenOctree(root);

    console.log(nodeList);
    // console.log(nodeObjectIndices);
    // console.log(nodeObjectRanges);
    
    connectNodeList(nodeList, program);

    connectObjectIndices(nodeObjectIndices, program);

    connectNodeObjectRanges(nodeObjectRanges, program);

}

function connectNodeList(nodeList, program){

    const { texData, nodeCount } = Encoder.encodeNodeListTexture(nodeList);

    // console.log(texData);

    const locNodeTex = gl.getUniformLocation(program, "u_nodeTexture");

    createFloatTexture(gl, texData, 4, nodeCount, gl.TEXTURE0);

    gl.uniform1i(locNodeTex, 0);            // ✅ 告诉 GLSL：使用第 0 号纹理单元
}

function connectObjectIndices(nodeObjectIndices, program){

    const { texData, nodeCount } = Encoder.encodeNodeObjectIndicesTexture(nodeObjectIndices);
// console.log(texData);
    const uNnodeObjectIndicesTex = gl.getUniformLocation(program, "u_nodeObjectIndicesTex");

    createFloatTexture(gl, texData, 1, nodeCount, gl.TEXTURE1);

    gl.uniform1i(uNnodeObjectIndicesTex, 1);
}

function connectNodeObjectRanges(nodeObjectRanges, program){

    const { texData, nodeCount } = Encoder.encodeNodeObjectRangesTexture(nodeObjectRanges);
// console.log(texData);
    const uNnodeObjectIndicesTex = gl.getUniformLocation(program, "u_nodeObjectRangesTex");

    createFloatTexture(gl, texData, 1, nodeCount, gl.TEXTURE2);

    gl.uniform1i(uNnodeObjectIndicesTex, 2);
}


function createFloatTexture(gl, texData, width, height, textureUnit) {
    const tex = gl.createTexture();

    gl.activeTexture(textureUnit);           // ✅ 激活传入的纹理单元
    gl.bindTexture(gl.TEXTURE_2D, tex);      // ✅ 绑定纹理到这个单元

    gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA32F,
        width, height,
        0,
        gl.RGBA,
        gl.FLOAT,
        texData
    );
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return tex;
}


window.addEventListener('keydown', (e) => {
    switch(e.key){
        case "w":
            cameraPhi -= 5;
            break;
        case "s":
            cameraPhi += 5;
            break;
        case "a":
            camereTheta -=5;
            break;
        case "d":
            camereTheta += 5;
            break;
        case "q":
            cameraRadius +=1;
            break;
        case "e":
            cameraRadius = Math.max(cameraRadius - 1, 0);
            break;
        case "i":
            lightPhi -= 5;
            break;
        case "k":
            lightPhi += 5;
            break;
        case "j":
            lightTheta -=5;
            break;
        case "l":
            lightTheta += 5;
            break;
        case "u":
            lightRadius +=1;
            break;
        case "o":
            lightRadius = Math.max(lightRadius - 1, 0);
            break;
    }
});

function getCameraPos(radius, thetaR, phiR) {
    const degToRad = Math.PI / 180;
    const theta = thetaR * degToRad;
    const phi = phiR * degToRad;

    const x = radius * Math.sin(phi) * Math.cos(theta);
    const y = radius * Math.sin(phi) * Math.sin(theta);
    const z = radius * Math.cos(phi);
    return [x, y, z];
}

/**
 * 加载 shader 源码
 * @param {string} url 着色器源码文件路径
 * @returns {Promise<string>}
 */
async function loadShaderSource(url) {
    const response = await fetch(url);
    return response.text();
}

/**
 * 创建并编译 shader
 * @param {WebGLRenderingContext} gl
 * @param {number} type gl.VERTEX_SHADER 或 gl.FRAGMENT_SHADER
 * @param {string} source GLSL 源码
 * @returns {WebGLShader | null}
 */
function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error("Shader 编译错误:", gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }

    return shader;
}

/**
 * 创建并链接 shader 程序
 * @param {WebGLRenderingContext} gl
 * @param {string} vsSource 顶点着色器源码
 * @param {string} fsSource 片段着色器源码
 * @returns {WebGLProgram | null}
 */
function createProgram(gl, vsSource, fsSource) {
    const vertexShader = createShader(gl, gl.VERTEX_SHADER, vsSource);
    const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fsSource);
    if (!vertexShader || !fragmentShader) return null;

    const program = gl.createProgram();
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        console.error("程序链接错误:", gl.getProgramInfoLog(program));
        gl.deleteProgram(program);
        return null;
    }

    return program;
}

