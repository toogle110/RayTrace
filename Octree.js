import { spheres, boxes, pyramids, sceneBounds } from './senceObject.js';
export class OctreeNode {
    constructor(bounds, depth = 0) {
        this.bounds = bounds; // { min: [x, y, z], max: [x, y, z] }
        this.depth = depth;
        this.children = [];
        this.objects = [];
    }

    insert(object, maxDepth = 6, maxObjects = 4) {
        // 如果还没分裂且尚未达到最大深度，就先判断是否需要分裂
        if (this.children.length === 0 && this.depth < maxDepth) {
            if (this.objects.length >= maxObjects) {
                this.subdivide();

                // 将当前 objects 中的已有对象重新分发到子节点中
                for (const existingObject of this.objects) {
                    for (const child of this.children) {
                        let intersects = OctreeNode.getIntersection(child.bounds, existingObject);
                        if (intersects) {
                            child.insert(existingObject, maxDepth, maxObjects);
                        }
                    }
                }

                this.objects = []; // 清空当前对象列表，防止非叶节点持有对象
            }
        }

        // 如果已经是叶子节点（没有子节点），直接存储
        if (this.children.length === 0) {
            this.objects.push(object);
            return;
        }

        // 已分裂：尝试插入子节点
        for (const child of this.children) {
            let intersects = OctreeNode.getIntersection(child.bounds, object);
            if (intersects) {
                child.insert(object, maxDepth, maxObjects);
            }
        }
    }

    static getIntersection(bounds, object) {


        // if(bounds.max[0] == 0 && bounds.max[1] == 10 && bounds.max[2] == -5 
        //     && bounds.
        // )




        if (object.index < spheres.length) {
            return OctreeNode.intersectsSphere(bounds, object.center, object.radius);
        } else if (object.index < spheres.length + boxes.length) {
            return OctreeNode.intersectsBox(bounds, object.center, object.size);
        } else if (object.index < spheres.length + boxes.length + pyramids.length) {
            return OctreeNode.intersectsPyramid(bounds, object.center, object.height, object.base);
        }
        return false;
    }

    static intersectsPyramid(bounds, center, height, base) {

        const size = [
            base,
            base,
            height
        ];

        const boxCenter = [
            center[0],
            center[1],
            center[2] + height * 0.5
        ];

        return OctreeNode.intersectsBox(bounds, boxCenter, size);
    }

    subdivide() {
        const { min, max } = this.bounds;
        const center = [
            (min[0] + max[0]) / 2,
            (min[1] + max[1]) / 2,
            (min[2] + max[2]) / 2
        ];

        for (let x = 0; x <= 1; x++) {
            for (let y = 0; y <= 1; y++) {
                for (let z = 0; z <= 1; z++) {
                    const newMin = [
                        x === 0 ? min[0] : center[0],
                        y === 0 ? min[1] : center[1],
                        z === 0 ? min[2] : center[2]
                    ];
                    const newMax = [
                        x === 0 ? center[0] : max[0],
                        y === 0 ? center[1] : max[1],
                        z === 0 ? center[2] : max[2]
                    ];
                    this.children.push(new OctreeNode({ min: newMin, max: newMax }, this.depth + 1));
                }
            }
        }
    }

    static intersectsSphere(bounds, center, radius) {
        // AABB vs Sphere test
        let distSq = 0;
        for (let i = 0; i < 3; i++) {
            const v = center[i];
            if (v < bounds.min[i]) distSq += (bounds.min[i] - v) ** 2;
            else if (v > bounds.max[i]) distSq += (v - bounds.max[i]) ** 2;
        }
        return distSq <= radius * radius;
    }

    static intersectsBox(bounds, center, size) {

        const objMin = [
            center[0] - size[0] * 0.5,
            center[1] - size[1] * 0.5,
            center[2] - size[2] * 0.5
        ];

        const objMax = [
            center[0] + size[0] * 0.5,
            center[1] + size[1] * 0.5,
            center[2] + size[2] * 0.5
        ];



        for (let i = 0; i < 3; i++) {
            if (bounds.max[i] < objMin[i] || bounds.min[i] > objMax[i]) {
                return false; // 分离轴存在，盒子不相交
            }
        }
        return true; // 所有轴都重叠，相交
    }

    // 可选：导出成 flat 数组用于传入 GPU（纹理/SSBO）
    flattenOctree(root) {
        const nodeList = [];
        const nodeObjectIndices = [];
        const nodeObjectRanges = [];

        this._flattenNode(root, -1, nodeList, nodeObjectIndices, nodeObjectRanges);

        return {
            nodeList,
            nodeObjectIndices,
            nodeObjectRanges
        };
    }

    _flattenNode(node, parentIndex, nodeList, nodeObjectIndices, nodeObjectRanges) {
        const index = nodeList.length;

        // 添加当前节点包含的所有物体索引（假设每个 object 都有 .index）
        const objectStart = nodeObjectIndices.length;
        for (const obj of node.objects) {
            nodeObjectIndices.push(obj.index);
        }
        const objectCount = node.objects.length;
        nodeObjectRanges.push([objectStart, objectCount]);

        // 添加当前节点到列表
        const nodeData = {
            bounds: node.bounds,
            objects: node.objects,
            children: [],
            parentIndex
        };
        nodeList.push(nodeData);

        // 递归展开子节点
        for (const child of node.children) {
            const childIndex = this._flattenNode(child, index, nodeList, nodeObjectIndices, nodeObjectRanges);
            nodeData.children.push(childIndex);
        }

        return index;
    }
}
