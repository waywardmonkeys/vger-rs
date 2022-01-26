

/// Filled circle.
let vgerCircle = 0;

/// Stroked arc.
let vgerArc = 1;

/// Rounded corner rectangle.
let vgerRect = 2;

/// Stroked rounded rectangle.
let vgerRectStroke = 3;

/// Single-segment quadratic bezier curve.
let vgerBezier = 4;

/// line segment
let vgerSegment = 5;

/// Multi-segment bezier curve.
let vgerCurve = 6;

/// Connection wire. See https://www.shadertoy.com/view/NdsXRl
let vgerWire = 7;

/// Text rendering.
let vgerGlyph = 8;

/// Path fills.
let vgerPathFill = 9;

struct vgerPrim {

    /// Type of primitive.
    prim_type: u32;

    /// Stroke width.
    width: f32;

    /// Radius of circles. Corner radius for rounded rectangles.
    radius: f32;

    /// Control vertices.
    cvs: array<vec2<f32>,3>;

    /// Start of the control vertices, if they're in a separate buffer.
    start: u32;

    /// Number of control vertices (vgerCurve and vgerPathFill)
    count: u32;

    /// Index of paint applied to drawing region.
    paint: u32;

    /// Glyph region index. (used internally)
    glyph: u32;

    /// Index of transform applied to drawing region. (used internally)
    xform: u32;

    /// Min and max coordinates of the quad we're rendering. (used internally)
    quad_bounds: array<vec2<f32>,2>;

    /// Min and max coordinates in texture space. (used internally)
    tex_bounds: array<vec2<f32>, 2>;

};

fn proj(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return normalize(a) * dot(a,b) / length(a);
}

fn orth(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return b - proj(a, b);
}

fn rot90(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(-p.y, p.x);
}

// From https://www.iquilezles.org/www/articles/distfunctions2d/distfunctions2d.htm
// See also https://www.shadertoy.com/view/4dfXDn

fn sdCircle(p: vec2<f32>, r: f32) -> f32
{
    return length(p) - r;
}

fn sdBox(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32
{
    let d = abs(p)-b+r;
    return length(max(d,vec2<f32>(0.0, 0.0))) + min(max(d.x,d.y),0.0)-r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32
{
    let pa = p-a;
    let ba = b-a;
    let h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

fn sdSegment2(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, width: f32) -> f32
{
    let u = normalize(b-a);
    let v = rot90(u);

    var pp = p;
    pp = pp - (a+b)/2.0;
    pp = pp * mat2x2<f32>(u, v);
    return sdBox(pp, vec2<f32>(length(b-a)/2.0, width/2.0), 0.0);
}

// sca is {sin,cos} of orientation
// scb is {sin,cos} of aperture angle
fn sdArc(p: vec2<f32>, sca: vec2<f32>, scb: vec2<f32>, ra: f32, rb: f32 ) -> f32
{
    var pp = p * mat2x2<f32>(vec2<f32>(sca.x,sca.y),vec2<f32>(-sca.y,sca.x));
    pp.x = abs(pp.x);
    var k = 0.0;
    if (scb.y*pp.x>scb.x*pp.y) {
        k = dot(pp,scb);
    } else {
        k = length(pp);
    }
    return sqrt( dot(pp,pp) + ra*ra - 2.0*ra*k ) - rb;
}

fn dot2(v: vec2<f32>) -> f32 {
    return dot(v,v);
}

fn sdBezier(pos: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32> ) -> f32
{
    let a = B - A;
    let b = A - 2.0*B + C;
    let c = a * 2.0;
    let d = A - pos;
    let kk = 1.0/dot(b,b);
    let kx = kk * dot(a,b);
    let ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    let kz = kk * dot(d,a);
    var res = 0.0;
    let p = ky - kx*kx;
    let p3 = p*p*p;
    let q = kx*(2.0*kx*kx + -3.0*ky) + kz;
    var h = q*q + 4.0*p3;
    if( h >= 0.0)
    {
        h = sqrt(h);
        let x = (vec2<f32>(h,-h)-q)/2.0;
        let uv = sign(x)*pow(abs(x), vec2<f32>(1.0/3.0));
        let t = clamp( uv.x+uv.y-kx, 0.0, 1.0 );
        res = dot2(d + (c + b*t)*t);
    }
    else
    {
        let z = sqrt(-p);
        let v = acos( q/(p*z*2.0) ) / 3.0;
        let m = cos(v);
        let n = sin(v)*1.732050808;
        let t = clamp(vec3<f32>(m+m,-n-m,n-m)*z-kx, vec3<f32>(0.0), vec3<f32>(1.0));
        res = min( dot2(d+(c+b*t.x)*t.x),
                   dot2(d+(c+b*t.y)*t.y) );
        // the third root cannot be the closest
        // res = min(res,dot2(d+(c+b*t.z)*t.z));
    }
    return sqrt( res );
}

fn sdSubtract(d1: f32, d2: f32) -> f32
{
    return max(-d1, d2);
}

fn sdPie(p: vec2<f32>, n: vec2<f32>) -> f32
{
    return abs(p).x * n.y + p.y*n.x;
}

/// Arc with square ends.
fn sdArc2(p: vec2<f32>, sca: vec2<f32>, scb: vec2<f32>, radius: f32, width: f32) -> f32
{
    // Rotate point.
    let pp = p * mat2x2<f32>(sca,vec2<f32>(-sca.y,sca.x));
    return sdSubtract(sdPie(pp, vec2<f32>(scb.x, -scb.y)),
                     abs(sdCircle(pp, radius)) - width);
}

// From https://www.shadertoy.com/view/4sySDK

fn inv(M: mat2x2<f32>) -> mat2x2<f32> {
    return (1.0 / determinant(M)) * mat2x2<f32>(
        vec2<f32>(M[1][1], -M[0][1]),
        vec2<f32>(-M[1][0], M[0][0]));
}

fn sdBezier2(uv: vec2<f32>, p0: vec2<f32>, p1: vec2<f32>, p2: vec2<f32>) -> f32 {

    let trf1 = mat2x2<f32>( vec2<f32>(-1.0, 2.0), vec2<f32>(1.0, 2.0) );
    let trf2 = inv(mat2x2<f32>(p0-p1, p2-p1));
    let trf=trf1*trf2;

    let uv2 = uv - p1;
    var xy =trf*uv2;
    xy.y = xy.y - 1.0;

    var gradient: vec2<f32>;
    gradient.x=2.*trf[0][0]*(trf[0][0]*uv2.x+trf[1][0]*uv2.y)-trf[0][1];
    gradient.y=2.*trf[1][0]*(trf[0][0]*uv2.x+trf[1][0]*uv2.y)-trf[1][1];

    return (xy.x*xy.x-xy.y)/length(gradient);
}

fn det(a: vec2<f32>, b: vec2<f32>) -> f32 { return a.x*b.y-b.x*a.y; }

fn closestPointInSegment( a: vec2<f32>, b: vec2<f32>) -> vec2<f32>
{
    let ba = b - a;
    return a + ba*clamp( -dot(a,ba)/dot(ba,ba), 0.0, 1.0 );
}

// From: http://research.microsoft.com/en-us/um/people/hoppe/ravg.pdf
fn get_distance_vector(b0: vec2<f32>, b1: vec2<f32>, b2: vec2<f32>) -> vec2<f32> {
    
    let a=det(b0,b2);
    let b=2.0*det(b1,b0);
    let d=2.0*det(b2,b1);

    let f=b*d-a*a;
    let d21=b2-b1; let d10=b1-b0; let d20=b2-b0;
    let gf=2.0*(b*d21+d*d10+a*d20);
    let gf=vec2<f32>(gf.y,-gf.x);
    let pp=-f*gf/dot(gf,gf);
    let d0p=b0-pp;
    let ap=det(d0p,d20); let bp=2.0*det(d10,d0p);
    // (note that 2*ap+bp+dp=2*a+b+d=4*area(b0,b1,b2))
    let t=clamp((ap+bp)/(2.0*a+b+d), 0.0 ,1.0);
    return mix(mix(b0,b1,t),mix(b1,b2,t),t);
    
}

fn sdBezierApprox(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32>) -> f32 {

    let v0 = normalize(B - A); let v1 = normalize(C - A);
    let det = v0.x * v1.y - v1.x * v0.y;
    if(abs(det) < 0.01) {
        return sdBezier(p, A, B, C);
    }

    return length(get_distance_vector(A-p, B-p, C-p));
}

fn sdBezierApprox2(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32>) -> f32 {
    return length(get_distance_vector(A-p, B-p, C-p));
}

struct BBox {
    min: vec2<f32>;
    max: vec2<f32>;
};

fn expand(box: BBox, p: vec2<f32>) -> BBox {
    var result: BBox;
    result.min = min(box.min, p);
    result.max = max(box.max, p);
    return result;
}

struct CVS {
    cvs: array<vec2<f32>>;
};

[[group(0), binding(0)]]
var<storage> cvs: CVS;

struct Prims {
    prims: array<vgerPrim>;
};

[[group(0), binding(1)]]
var<storage> prims: Prims;

fn sdPrimBounds(prim: vgerPrim) -> BBox {
    var b: BBox;
    switch (prim.prim_type) {
        case 0: { // vgerCircle
            b.min = prim.cvs[0] - prim.radius;
            b.max = prim.cvs[0] + prim.radius;
        }
        case 1: { // vgerArc
            b.min = prim.cvs[0] - prim.radius;
            b.max = prim.cvs[0] + prim.radius;
        }
        case 2: { // vgerRect
            b.min = prim.cvs[0];
            b.max = prim.cvs[1];
        }
        case 3: { // vgerRectStroke
            b.min = prim.cvs[0];
            b.max = prim.cvs[1];
        }
        case 4: { // vgerBezier
            b.min = min(min(prim.cvs[0], prim.cvs[1]), prim.cvs[2]);
            b.max = max(max(prim.cvs[0], prim.cvs[1]), prim.cvs[2]);
        }
        case 5: { // vgerSegment
            b.min = min(prim.cvs[0], prim.cvs[1]);
            b.max = max(prim.cvs[0], prim.cvs[1]);
        }
        case 6: { // vgerCurve
            b.min = vec2<f32>(1e10, 1e10);
            b.max = -b.min;
            for(var i: i32 = 0; i < i32(prim.count * 3u); i = i+1) {
                b = expand(b, cvs.cvs[i32(prim.start)+i]);
            }
        }
        case 7: { // vgerSegment
            b.min = min(prim.cvs[0], prim.cvs[1]);
            b.max = max(prim.cvs[0], prim.cvs[1]);
        }
        case 8: { // vgerGlyph
            b.min = prim.cvs[0];
            b.max = prim.cvs[1];
        }
        case 9: { // vgerPathFill
            b.min = vec2<f32>(1e10, 1e10);
            b.max = -b.min;
            for(var i: i32 = 0; i < i32(prim.count * 3u); i = i+1) {
                b = expand(b, cvs.cvs[i32(prim.start)+i]);
            }
        }
        default: {}
    }
    return b;
}

fn lineTest(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>) -> bool {

    let cs = i32(A.y < p.y) * 2 + i32(B.y < p.y);

    if(cs == 0 || cs == 3) { return false; } // trivial reject

    let v = B - A;

    // Intersect line with x axis.
    let t = (p.y-A.y)/v.y;

    return (A.x + t*v.x) > p.x;

}

/// Is the point with the area between the curve and line segment A C?
fn bezierTest(p: vec2<f32>, A: vec2<f32>, B: vec2<f32>, C: vec2<f32>) -> bool {

    // Compute barycentric coordinates of p.
    // p = s * A + t * B + (1-s-t) * C
    let v0 = B - A; let v1 = C - A; let v2 = p - A;
    let det = v0.x * v1.y - v1.x * v0.y;
    let s = (v2.x * v1.y - v1.x * v2.y) / det;
    let t = (v0.x * v2.y - v2.x * v0.y) / det;

    if(s < 0.0 || t < 0.0 || (1.0-s-t) < 0.0) {
        return false; // outside triangle
    }

    // Transform to canonical coordinte space.
    let u = s * 0.5 + t;
    let v = t;

    return u*u < v;

}

fn sdPrim(prim: vgerPrim, p: vec2<f32>, exact: bool, filterWidth: f32) -> f32 {
    var d = 1e10;
    var s = 1;
    switch(prim.prim_type) {
        case 0: { // vgerCircle
            d = sdCircle(p - prim.cvs[0], prim.radius);
        }
        case 1: { // vgerArc
            d = sdArc2(p - prim.cvs[0], prim.cvs[1], prim.cvs[2], prim.radius, prim.width/2.0);
        }
        case 2: { // vgerRect
            let center = 0.5*(prim.cvs[1] + prim.cvs[0]);
            let size = prim.cvs[1] - prim.cvs[0];
            d = sdBox(p - center, 0.5*size, prim.radius);
        }
        case 3: { // vgerRectStroke
            let center = 0.5*(prim.cvs[1] + prim.cvs[0]);
            let size = prim.cvs[1] - prim.cvs[0];
            d = abs(sdBox(p - center, 0.5*size, prim.radius)) - prim.width/2.0;
        }
        case 4: { // vgerBezier
            d = sdBezierApprox(p, prim.cvs[0], prim.cvs[1], prim.cvs[2]) - prim.width;
        }
        case 5: { // vgerSegment
            d = sdSegment2(p, prim.cvs[0], prim.cvs[1], prim.width);
        }
        case 6: { // vgerCurve
            //for(var i=0; i<i32(prim.count); i = i+1) {
            //    let j = prim.start + 3*i;
            //    d = min(d, sdBezierApprox(p, cvs[j], cvs[j+1], cvs[j+2]));
            //}
        }
        case 7: { // vgerSegment
            d = sdSegment2(p, prim.cvs[0], prim.cvs[1], prim.width);
        }
        case 8: { // vgerGlyph
            let center = 0.5*(prim.cvs[1] + prim.cvs[0]);
            let size = prim.cvs[1] - prim.cvs[0];
            d = sdBox(p - center, 0.5*size, prim.radius);
        }
        case 9: { // vgerPathFill
            
        }
        default: { }
    }
    return d;
}

fn vs_main() { }