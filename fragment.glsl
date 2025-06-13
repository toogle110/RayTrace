#version 300 es
precision highp float;

out vec4 outColor;

#define MAX_SPHERES 10  // 最大支持的球体数量（对应 JS 中的 uniform 数组最大长度）

// === 来自 JS 的 uniform 变量 ===

// 相机位置
uniform vec3 u_cameraPos;

// 相机上方
uniform vec3 u_cameraUp;

uniform vec3 u_lightPosition;

// 屏幕分辨率（单位像素）：用于将像素坐标标准化到 [-1, 1]
uniform vec2 u_resolution;

// 当前时间（单位秒）：可用于动画，但此处暂未使用
uniform float u_time;

uniform sampler2D u_nodeTexture;           // 存储八叉树结构信息
uniform sampler2D u_nodeObjectIndicesTex;  // 存储物体索引列表
uniform sampler2D u_nodeObjectRangesTex;   // 存储每个节点的物体范围

// 球体
// 所有球体的位置数组，长度最多为 MAX_SPHERES，每个 vec3 表示球心位置
uniform vec3 u_sphereCenters[MAX_SPHERES];
// 所有球体的半径数组，最多 MAX_SPHERES 个 float
uniform float u_sphereRadii[MAX_SPHERES];
// 实际传入的球体数量（避免遍历空数组）
uniform int u_sphereCount;
uniform vec3 u_sphereColors[MAX_SPHERES];
uniform float u_sphereReflectivitys[MAX_SPHERES];
uniform int u_sphereType[MAX_SPHERES];
uniform float u_sphereIor[MAX_SPHERES];


// 立方体
uniform int u_boxCount;
uniform vec3 u_boxCenters[MAX_SPHERES];
uniform vec3 u_boxSizes[MAX_SPHERES];
uniform vec3 u_boxColors[MAX_SPHERES];
uniform float u_boxReflectivitys[MAX_SPHERES];
uniform int u_boxType[MAX_SPHERES];
uniform float u_boxIor[MAX_SPHERES];

// 棱锥
uniform int u_pyramidCount;
uniform vec3 u_pyramidCenters[MAX_SPHERES];
uniform float u_pyramidHeights[MAX_SPHERES];
uniform float u_pyramidBases[MAX_SPHERES];
uniform vec3 u_pyramidColors[MAX_SPHERES];
uniform float u_pyramidReflectivitys[MAX_SPHERES];
uniform int u_pyramidType[MAX_SPHERES];
uniform float u_pyramidIor[MAX_SPHERES];


int reflMaxTime = 10;
float ambient = 0.05;

const int MAX_STACK_SIZE = 64;
int stack[MAX_STACK_SIZE];
int stackPtr = 0;


// 结果结构体：记录最近命中的物体信息
struct Hit {
    float t;
    int type;          // 0:未命中, 1:漫反射, 2:镜面反射, 3:折射(玻璃)
    vec3 position;     // 交点位置
    vec3 normal;       // 法线
    vec3 incidentDir;  // 入射光
    vec3 color;        // 颜色
    float reflectivity; // 反射率
    float ior;         // 折射率(Index of Refraction)
};



// Schlick菲涅尔近似
float fresnelSchlick(vec3 incident, vec3 normal, float ior) {
    float cosi = clamp(dot(incident, normal), -1.0, 1.0);
    float etai = 1.0, etat = ior;
    
    if (cosi > 0.0) {
        float temp = etai;
        etai = etat;
        etat = temp;
    }
    
    float sint = etai / etat * sqrt(max(0.0, 1.0 - cosi * cosi));
    if (sint >= 1.0) {
        // 全内反射
        return 1.0;
    }
    
    float cost = sqrt(max(0.0, 1.0 - sint * sint));
    cosi = abs(cosi);
    float Rs = ((etat * cosi) - (etai * cost)) / ((etat * cosi) + (etai * cost));
    float Rp = ((etai * cosi) - (etat * cost)) / ((etai * cosi) + (etat * cost));
    return (Rs * Rs + Rp * Rp) / 2.0;
}





// 光线与单个球体求交，返回最近的交点 t，若无交点则返回 -1
Hit intersectSphere(Hit hit, vec3 ro, vec3 rd, int index) {
    vec3 center = u_sphereCenters[index];
    float radius = u_sphereRadii[index];
    vec3 color = u_sphereColors[index];
    float reflectivity = u_sphereReflectivitys[index];

    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b*b - c;
    if (h > 0.0) {
        float sqrtH = sqrt(h);
        float t0 = -b - sqrtH;
        if (t0 > 0.001 && t0 < hit.t) {
            hit.t = t0;
            hit.type = u_sphereType[index];
            hit.position = ro + rd * t0;
            hit.normal = normalize(hit.position - center);
            hit.color = color;
            hit.reflectivity = reflectivity;
            hit.ior = u_sphereIor[index];
        }
    }

    return hit;
}

// 光线与轴对齐立方体求交
Hit intersectBox(Hit hit, vec3 ro, vec3 rd, int index) {
    vec3 boxMin = u_boxCenters[index] - u_boxSizes[index];
    vec3 boxMax = u_boxCenters[index] + u_boxSizes[index];
    vec3 color = u_boxColors[index];
    float reflectivity = u_boxReflectivitys[index];


    vec3 tMin = (boxMin - ro) / rd;
    vec3 tMax = (boxMax - ro) / rd;
    
    vec3 t1 = min(tMin, tMax);
    vec3 t2 = max(tMin, tMax);

    float tNear = max(max(t1.x, t1.y), t1.z);
    float tFar  = min(min(t2.x, t2.y), t2.z);

    if (tNear > 0.001 && tNear < tFar && tNear < hit.t) {
        hit.t = tNear;
        hit.type = u_boxType[index];
        hit.position = ro + rd * tNear;

        // 计算法线（哪个轴命中）
        vec3 normal = vec3(0.0);
        vec3 p = hit.position;
        float bias = 0.001;
        if (abs(p.x - boxMin.x) < bias) normal = vec3(-1, 0, 0);
        else if (abs(p.x - boxMax.x) < bias) normal = vec3(1, 0, 0);
        else if (abs(p.y - boxMin.y) < bias) normal = vec3(0, -1, 0);
        else if (abs(p.y - boxMax.y) < bias) normal = vec3(0, 1, 0);
        else if (abs(p.z - boxMin.z) < bias) normal = vec3(0, 0, -1);
        else if (abs(p.z - boxMax.z) < bias) normal = vec3(0, 0, 1);

        hit.normal = normal;

        hit.color = color;
        hit.reflectivity = reflectivity;
        hit.ior = u_boxIor[index];
    }

    return hit;
}

// 参数：ro 起点；rd 方向
// 棱锥参数：中心 (cx, cy, cz)，高度 h，底边长度 size
Hit intersectPyramid(Hit hit, vec3 ro, vec3 rd, int index) {
    vec3 center = u_pyramidCenters[index];
    float height = u_pyramidHeights[index];
    float size = u_pyramidBases[index];
    vec3 color = u_pyramidColors[index];
    float reflectivity = u_pyramidReflectivitys[index];

    // 移动到局部空间
    vec3 localRo = ro - center;
    vec3 localRd = rd;

    float halfSize = size * 0.5;
    float tMin = hit.t;

    // 射线与底面（z = 0）求交
    if (abs(localRd.z) > 0.001) {
        float t = -localRo.z / localRd.z;
        vec3 p = localRo + localRd * t;
        if (abs(p.x) <= halfSize && abs(p.y) <= halfSize && t > 0.001 && t < tMin) {
            tMin = t;
            hit.t = t;
            hit.type = u_pyramidType[index];
            hit.ior = u_pyramidIor[index];
            hit.position = ro + rd * t;
            hit.normal = vec3(0, 0, -1); // 底面朝 -z
            hit.color = color;
            hit.reflectivity = reflectivity;
        }
    }

    // 与四个侧面（三角面）求交
    vec3 apex = vec3(0, 0, height);
    vec3 corners[4] = vec3[4](
        vec3(-halfSize, -halfSize, 0),
        vec3( halfSize, -halfSize, 0),
        vec3( halfSize,  halfSize, 0),
        vec3(-halfSize,  halfSize, 0)
    );

    for (int i = 0; i < 4; i++) {
        vec3 a = apex;
        vec3 b = corners[i];
        vec3 c = corners[(i + 1) % 4];

        vec3 edge1 = b - a;
        vec3 edge2 = c - a;
        vec3 h = cross(localRd, edge2);
        float det = dot(edge1, h);
        if (abs(det) < 0.0001) continue;

        float invDet = 1.0 / det;
        vec3 s = localRo - a;
        float u = dot(s, h) * invDet;
        if (u < 0.0 || u > 1.0) continue;

        vec3 q = cross(s, edge1);
        float v = dot(localRd, q) * invDet;
        if (v < 0.0 || u + v > 1.0) continue;

        float t = dot(edge2, q) * invDet;
        if (t > 0.001 && t < tMin) {
            tMin = t;
            hit.t = t;
            hit.type = u_pyramidType[index];
            hit.ior = u_pyramidIor[index];
            hit.position = ro + rd * t;

            // 法线（朝外）
            vec3 normal = normalize(cross(edge2, edge1)); // 注意交换
            hit.normal = normal;
            hit.color = color;
            hit.reflectivity = reflectivity;
        }
    }

    return hit;
}

bool rayAABB(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
    vec3 invDir = 1.0 / rd;

    vec3 t0 = (bmin - ro) * invDir;
    vec3 t1 = (bmax - ro) * invDir;

    vec3 tmin = min(t0, t1);
    vec3 tmax = max(t0, t1);

    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar  = min(min(tmax.x, tmax.y), tmax.z);

    // 判断是否从盒子外部射入（tNear >= 0），且有交点
    return (tFar >= tNear) && (tFar >= 0.0);
}



int getObjectType(int objIndex){
    if(objIndex < u_sphereCount){
        return 1;
    }else if(objIndex < u_sphereCount + u_boxCount){
        return 2;
    }else if(objIndex < u_sphereCount + u_boxCount + u_pyramidCount){
        return 3;
    }
    return -1;
}

Hit intersectObject(vec3 ro, vec3 rd, int objIndex) {
    Hit hit;
    hit.t = 1e20;
    hit.type = 0;
    hit.incidentDir = rd;
    hit.color = vec3(0.0); // 默认颜色

    int type = getObjectType(objIndex); // 你需要从一个纹理中读取
    if (type == 1) {
        hit = intersectSphere(hit, ro, rd, objIndex);
    } else if (type == 2) {
        hit = intersectBox(hit, ro, rd, objIndex - u_sphereCount);
    } else if (type == 3) {
        hit = intersectPyramid(hit, ro, rd, objIndex - u_sphereCount - u_boxCount);
    }


    return hit;
}

// 入栈操作
void push(int value) {
    if (stackPtr < MAX_STACK_SIZE) {
        stack[stackPtr++] = value;
    }
}

// 出栈操作
int pop() {
    if (stackPtr > 0) {
        return stack[--stackPtr];
    }
    return -1; // 空栈时返回无效索引
}

// ro 出发点；ed 光线方向
Hit intersectScene(vec3 ro, vec3 rd) {
    Hit hit;
    hit.t = 1e20;
    hit.type = 0;
    hit.incidentDir = rd;
    hit.color = vec3(0.0); // 默认颜色

    // ---- 手动栈 ----
    push(0);

    while (stackPtr > 0) {

        int currentNode = pop();

        // 读取 AABB
        vec4 aabb1 = texelFetch(u_nodeTexture, ivec2(0, currentNode), 0);
        vec4 aabb2 = texelFetch(u_nodeTexture, ivec2(1, currentNode), 0);
        

        vec3 bmin = vec3(aabb1.x, aabb1.y, aabb1.z);
        vec3 bmax = vec3(aabb1.w, aabb2.x, aabb2.y);


        if (!rayAABB(ro, rd, bmin, bmax)) {
            continue;
        }


        int objectNum = int(aabb2.w);
        bool isLeaf = true;
        for(int i = 0; i < 2; i++){
            vec4 aabb = texelFetch(u_nodeTexture, ivec2(2 + i, currentNode), 0);
            if(aabb.x > 0.0 || aabb.y > 0.0 || aabb.z > 0.0 || aabb.w > 0.0){
                isLeaf = false;
            }
        }
                


        if (isLeaf) {
            // 处理叶子节点中的对象
            vec4 range = texelFetch(u_nodeObjectRangesTex, ivec2(0, floor(float(currentNode) / 2.0)), 0);
            int start;
            int count;
            if(currentNode % 2 == 0){
                start = int(range.x);
                count = int(range.y);
            }else{
                start = int(range.z);
                count = int(range.w);
            }


            Hit tHit;
            for (int i = 0; i < count; i++) {
                int objIndex;

                ivec2 coord = ivec2(0, floor(float(start + i) / 4.0));  // 固定宽度4
                vec4 block = texelFetch(u_nodeObjectIndicesTex, coord, 0);
                int ind = (start + i) % 4;
                if(ind == 0){
                    objIndex = int(block.x);
                }else if (ind == 1){
                    objIndex = int(block.y);
                }else if (ind == 2){
                    objIndex = int(block.z);
                }else{
                    objIndex = int(block.w);
                }

                tHit = intersectObject(ro, rd, objIndex);
                if(hit.t > tHit.t){
                    hit = tHit;
                }

            }

            continue;
        }



        // 子节点压栈（从后向前压栈以近似 DFS）
        for(int i = 2; i < 4; i++){
            vec4 aabb3 = texelFetch(u_nodeTexture, ivec2(i, currentNode), 0);

            for(int j = 0; j < 4; j++){
                int childIndex;
                if(j == 0){
                    childIndex = int(aabb3.w);
                }else if(j == 1){
                    childIndex = int(aabb3.z);
                }else if(j == 2){
                    childIndex = int(aabb3.y);
                }else if(j == 3){
                    childIndex = int(aabb3.x);
                }

                if (childIndex >= 0 && stackPtr < MAX_STACK_SIZE) {
                    push(childIndex);
                }
            }

        }

    }

    return hit;
}






// 简易随机函数（需要替换为更好的实现）
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float rand(vec3 co) {
    return rand(co.xy + co.z);
}

float hash(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float fresnelSchlick(float cosTheta, float etai, float etat) {
    float r0 = (etai - etat) / (etai + etat);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
}


void setupRayDirection(out vec3 ro, out vec3 rd) {
    // 将屏幕坐标映射到 [-1, 1] 范围的标准化设备坐标
    vec2 uv = (gl_FragCoord.xy / u_resolution) * 2.0 - 1.0;
    uv.x *= u_resolution.x / u_resolution.y; // 纠正宽高比

    // 设置摄像机的朝向参数
    vec3 cameraTarget = vec3(0.0);                        // 摄像机目标点（视点）
    vec3 forward = normalize(cameraTarget - u_cameraPos); // 摄像机前方向
    vec3 right = normalize(cross(forward, u_cameraUp));   // 摄像机右方向
    vec3 up = cross(right, forward);                      // 摄像机正上方向（重计算保证正交）

    // 输出光线的起点（摄像机位置）
    ro = u_cameraPos;

    // 输出光线的方向（通过当前像素射出）
    rd = normalize(forward + uv.x * right + uv.y * up);
}

bool handleGlassMaterial(inout vec3 currOrigin, inout vec3 currDir, inout vec3 throughput, inout vec3 color, Hit hit, int reflTime) {
    // 计算入射角的余弦值，限制在[-1,1]范围
    float cosi = clamp(dot(currDir, hit.normal), -1.0, 1.0);

    // 折射率初始化：etai = 光线当前介质的折射率（空气为1）
    // etat = 目标介质（玻璃）的折射率，从hit中获取
    float etai = 1.0;
    float etat = hit.ior;

    vec3 n = hit.normal;

    // 如果cosi>0，说明光线从内部射出，法线方向取反，折射率交换
    if (cosi > 0.0) {
        n = -hit.normal;
        float temp = etai; etai = etat; etat = temp;
    } else {
        // 保持cosi为入射角的绝对值
        cosi = -cosi;
    }

    // 折射率比
    float eta = etai / etat;
    // 计算折射判别式，判断是否发生全反射
    float k = 1.0 - eta * eta * (1.0 - cosi * cosi);
    // 计算菲涅尔反射系数，决定反射和折射光比例
    float F = fresnelSchlick(cosi, etai, etat);
    bool totalInternalReflection = (k < 0.0); // k<0 表示发生全内反射

    // 计算反射方向和起点（偏移避免自交）
    vec3 reflectDir = reflect(currDir, hit.normal);
    vec3 reflectOrigin = hit.position + hit.normal * 1e-4;

    // 计算折射方向和起点（偏移避免自交）
    vec3 refractDir = normalize(eta * currDir + (eta * cosi - sqrt(k)) * n);
    vec3 refractOrigin = hit.position - hit.normal * 1e-5;

    // 玻璃材质的吸收系数，用于模拟光在玻璃中的衰减（颜色偏黄青）
    vec3 absorptionCoeff = vec3(0.2, 0.15, 0.3);

    // 反射和折射颜色初始化
    vec3 reflectColor = vec3(0.0);
    vec3 refractColor = vec3(0.0);

    // 追踪反射光线，看它击中了什么
    Hit reflHit = intersectScene(reflectOrigin, reflectDir);
    if (reflHit.type != 0) {
        // 计算简单的漫反射光照（方向光）
        vec3 lightDir = normalize(u_lightPosition - reflHit.position);
        float diff = max(dot(reflHit.normal, lightDir), 0.0);
        reflectColor = reflHit.color * (diff + ambient);
    }

    // 如果未发生全内反射，则继续计算折射光线颜色
    if (!totalInternalReflection) {
        Hit refrHit = intersectScene(refractOrigin, refractDir);
        if (refrHit.type != 0) {
            // 计算光线在玻璃中传播距离，用于衰减吸收
            float distance = length(refrHit.position - hit.position);
            vec3 absorption = exp(-absorptionCoeff * distance);

            vec3 lightDir = normalize(u_lightPosition - refrHit.position);
            float diff = max(dot(refrHit.normal, lightDir), 0.0);

            // 折射光颜色，考虑光照和吸收
            refractColor = refrHit.color * (diff + ambient) * absorption;
        }
    }

    // 综合反射和折射贡献，乘以当前吞吐量，累积到最终颜色
    color += throughput * (F * reflectColor + (1.0 - F) * refractColor);

    currOrigin = refractOrigin;
    currDir = refractDir;
    // 吞吐量乘以折射比例及吸收衰减
    throughput *= (1.0 - F) * exp(-absorptionCoeff * 0.1);
    throughput = max(throughput, vec3(1e-4));


    if (!(dot(refractDir, refractDir) > 0.0)) {
        color = vec3(1.0, 0.0, 1.0); // Magenta: NaN 或非法方向
        return false;
    }

    return true; // 表示光线状态已更新，需继续追踪
}


// 根据击中信息和当前光线方向，计算 Blinn-Phong 模型的光照贡献
vec3 computeLighting(Hit hit, vec3 currDir) {
    // === 光照方向 ===
    vec3 lightDir = normalize(u_lightPosition - hit.position);

    // === 阴影检测 ===
    vec3 shadowOrigin = hit.position + hit.normal * 1e-4; // 避免自交
    Hit shadowHit = intersectScene(shadowOrigin, lightDir);
    float lightDist = length(u_lightPosition - hit.position);
    bool inShadow = (shadowHit.type != 0 && length(shadowHit.position - shadowOrigin) < lightDist);

    // === 视角和半程向量（用于高光） ===
    vec3 viewDir = -currDir;
    vec3 halfDir = normalize(lightDir + viewDir);

    float diff = 0.0;
    float spec = 0.0;
    if (!inShadow) {
        diff = max(dot(hit.normal, lightDir), 0.0);               // 漫反射
        spec = pow(max(dot(hit.normal, halfDir), 0.0), 32.0);     // 高光反射
    }

    // === 光照总和 ===
    vec3 lighting = vec3(0.0);
    lighting += diff * hit.color;        // 漫反射贡献
    lighting += spec * vec3(1.0);        // 镜面反射贡献（白色）
    lighting += ambient * hit.color;     // 环境光贡献
    return lighting;
}

vec3 sampleDiffuseDirection(vec3 normal, vec3 seed, int reflTime) {
    // 构造一个正交坐标系：tangent 和 bitangent 共同和法线 normal 构成局部空间
    // 先根据法线选择一个非平行向量用于叉乘，避免退化
    vec3 tangent = normalize(
        abs(normal.x) > 0.1 
        ? cross(normal, vec3(0.0, 1.0, 0.0))  // 法线 x 分量较大，选用 Y 轴向量
        : cross(normal, vec3(1.0, 0.0, 0.0))  // 法线 x 分量较小，选用 X 轴向量
    );
    // 计算切线空间的另一个正交向量 bitangent
    vec3 bitangent = cross(normal, tangent);

    // 生成两个随机数 r1, r2，用于极坐标采样
    // rand 用 seed 和 reflTime 保证采样随机但可复现
    float r1 = rand(seed.xy + float(reflTime));
    float r2 = rand(seed.yz + float(reflTime));

    // 计算极角 phi (0 ~ 2π)
    float phi = 2.0 * 3.1415926 * r1;
    // 计算半径的平方根，用于余弦加权采样（r分布）
    float r = sqrt(r2);

    // 将极坐标转换为局部半球方向（局部空间内）
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(1.0 - r2);  // 确保方向落在半球上 (z 为法线方向)

    vec3 localDir = vec3(x, y, z);

    // 将局部空间方向转换到世界空间
    vec3 worldDir = normalize(
        localDir.x * tangent +
        localDir.y * bitangent +
        localDir.z * normal
    );

    // 确保返回的方向在法线同侧（半球内）
    return dot(worldDir, normal) < 0.0 ? -worldDir : worldDir;
}

void main() {
    // 初始化相机位置(ro)和主射线方向(rd)
    vec3 ro, rd;
    setupRayDirection(ro, rd);

    // 初始化最终输出颜色和光能吞吐量（即路径颜色乘积）
    vec3 color = vec3(0.0);
    vec3 throughput = vec3(1.0);

    // 当前光线的起点和方向
    vec3 currOrigin = ro;
    vec3 currDir = rd;

    // 开始路径追踪（多次弹射）
    for (int reflTime = 0; reflTime < reflMaxTime; reflTime++) {

        // 计算当前光线与场景的交点
        Hit hit = intersectScene(currOrigin, currDir);

        // 若没有交点（hit.type == 0），即击中背景，退出循环
        if (hit.type == 0) break;

        // 若击中玻璃材质（type == 3），特殊处理折射与反射
        if (hit.type == 3) {
            if (handleGlassMaterial(currOrigin, currDir, throughput, color, hit, reflTime)) {
                // 若处理后光线已更新，继续下一个 bounce
                continue;
            }
        }

        // 计算当前击中点的直接光照（漫反射、镜面、阴影等）
        vec3 lighting = computeLighting(hit, currDir);

        // 将本次 bounce 的光照贡献累积到总颜色中
        color += throughput * lighting;

        // 准备下一次反弹方向和吞吐量
        if (hit.type == 1) {  // 漫反射材质
            // 半球余弦加权采样，生成新的随机方向
            currDir = sampleDiffuseDirection(hit.normal, currOrigin, reflTime);
            // 更新吞吐量，考虑表面颜色与反射率
            throughput *= hit.reflectivity * hit.color;

        } else if (hit.type == 2) {  // 镜面反射材质
            // 计算完美反射方向
            currDir = reflect(currDir, hit.normal);
            // 更新吞吐量，仅乘以反射率
            throughput *= hit.reflectivity;
        }

        // 起点略微偏移，避免自交（避免打到自身）
        currOrigin = hit.position + hit.normal * 1e-5;

        // 俄罗斯轮盘赌提前终止：提升效率，防止低能量光线无限 bounce
        if (reflTime > 2) {
            float continueProb = min(max(throughput.r, max(throughput.g, throughput.b)), 0.95);
            if (rand(currOrigin) > continueProb) break;
            // 若继续追踪，吞吐量需除以概率以保持能量守恒
            throughput /= continueProb;
        }
    }

    // === 后处理 ===

    // Reinhard 色调映射，避免颜色过亮
    color = color / (color + vec3(1.0));

    // Gamma 校正，使图像符合人眼感知
    color = pow(color, vec3(1.0 / 2.2));

    // 输出最终颜色
    outColor = vec4(color, 1.0);
}
