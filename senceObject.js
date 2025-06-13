
export const spheres = [
    { index:-1, center: [-2.0, -2.0, 0.0], radius: 1.0 , color: [1.0, 1.0, 1.0], reflectivity:0.9, type:3, ior:1.5},
    { index:-1, center: [0.0, 0.0, 5.0], radius: 1.0 , color: [1.0, 0.0, 0.0], reflectivity:0.001, type:1, ior:0},
    { index:-1, center: [0.0, 0.0, -3.0], radius: 2.0 , color: [0.0, 1.0, 0.0], reflectivity:0.001, type:1, ior:0}
];

export const boxes = [
    { index:-1, center: [-5.0, 0.0, 0.0], size: [2.0, 2.0, 2.0], color:[0.0, 0.0, 1.0], reflectivity:0.1, type:1, ior:0 },
    { index:-1, center: [0.0, 0.0, -8.0], size: [10.0, 10.0, 0.1], color:[0.05, 0.05, 0.05], reflectivity:0.9, type:2, ior:0 },
    { index:-1, center: [0.0, -10.0, 0.0], size: [10.0, 0.1, 10.0], color:[1.0, 1.0, 1.0], reflectivity:0.001, type:1, ior:0 }
];

export const pyramids = [
    { index:-1, center: [0.0, 0.0, 0.0], height: 2.0, base: 2.0, color:[0.1, 0.05, 0.2], reflectivity:0.9, type:3, ior:1.5 }
];

export const sceneBounds = {
    min: [-20, -20, -20],
    max: [20, 20, 20]
};


