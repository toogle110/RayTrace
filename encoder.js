export class Encoder {
    static encodeNodeListTexture(nodeList){
        const nodeCount = nodeList.length;
        const floatsPerNode = 16;
        const texData = new Float32Array(nodeCount * floatsPerNode);

        for (let i = 0; i < nodeCount; i++) {
            const node = nodeList[i];
            const offset = i * floatsPerNode;

            texData[offset + 0] = node.bounds.min[0];
            texData[offset + 1] = node.bounds.min[1];
            texData[offset + 2] = node.bounds.min[2];
            texData[offset + 3] = node.bounds.max[0];

            texData[offset + 4] = node.bounds.max[1];
            texData[offset + 5] = node.bounds.max[2];
            texData[offset + 6] = node.parentIndex;
            texData[offset + 7] = node.objects.length;

            for (let j = 0; j < 8; j++) {
                texData[offset + 8 + j] = node.children[j] !== undefined ? node.children[j] : -1;
            }
        }

        return { texData, nodeCount };
    }


    static encodeNodeObjectIndicesTexture(nodeObjectIndices){
        const nodeCount = Math.ceil(nodeObjectIndices.length / 4);
        const floatsPerNode = 4;
        const texData = new Float32Array(nodeCount * floatsPerNode);

        for (let i = 0; i < nodeCount; i++) {
            for (let j = 0; j < 4; j++) {
                const index = i * 4 + j;
                texData[i * 4 + j] = (index < nodeObjectIndices.length) ? nodeObjectIndices[index] : -1;
            }
        }

        return { texData, nodeCount };
    }

    static encodeNodeObjectRangesTexture(nodeObjectRanges){
        const nodeCount = Math.ceil(nodeObjectRanges.length / 2.0);
        const texData = new Float32Array(nodeCount * 4); // 每个 range 放在一行（RGBA）

        for (let i = 0; i < nodeCount; i++) {
            for(let j = 0; j < 2; j++){
                const ind = i * 2 + j;
                if(ind < nodeObjectRanges.length){
                    const [start, count] = nodeObjectRanges[ind];
                    texData[i * 4 + j * 2 + 0] = start;
                    texData[i * 4 + j * 2 + 1] = count;
                }
            }
            // const [start, count] = nodeObjectRanges[i * 2];
            // texData[i * 4 + 0] = start;
            // texData[i * 4 + 1] = count;

            // [start, count] = nodeObjectRanges[i * 2 + 1];
            // texData[i * 4 + 2] = start;     // padding
            // texData[i * 4 + 3] = count;     // padding
        }

        return { texData, nodeCount };
    }
}