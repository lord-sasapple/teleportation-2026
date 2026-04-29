using UnityEngine;

namespace X5Quest.Rendering
{
    [RequireComponent(typeof(MeshFilter))]
    [RequireComponent(typeof(MeshRenderer))]
    public sealed class InsideOutSphereRenderer : MonoBehaviour
    {
        [SerializeField] private int longitudeSegments = 96;
        [SerializeField] private int latitudeSegments = 48;
        [SerializeField] private float radius = 10f;
        [SerializeField] private Material material;

        private MeshRenderer meshRenderer;

        private void Awake()
        {
            meshRenderer = GetComponent<MeshRenderer>();
            GetComponent<MeshFilter>().mesh = BuildMesh();
            if (material == null)
            {
                material = new Material(Shader.Find("Unlit/Texture"));
            }
            meshRenderer.sharedMaterial = material;
        }

        public void SetTexture(Texture texture)
        {
            if (texture == null)
            {
                return;
            }
            meshRenderer.sharedMaterial.mainTexture = texture;
        }

        private Mesh BuildMesh()
        {
            var mesh = new Mesh { name = "InsideOutEquirectSphere" };
            var vertexCount = (longitudeSegments + 1) * (latitudeSegments + 1);
            var vertices = new Vector3[vertexCount];
            var uvs = new Vector2[vertexCount];
            var triangles = new int[longitudeSegments * latitudeSegments * 6];

            var vertex = 0;
            for (var lat = 0; lat <= latitudeSegments; lat++)
            {
                var v = (float)lat / latitudeSegments;
                var theta = v * Mathf.PI;
                var sinTheta = Mathf.Sin(theta);
                var cosTheta = Mathf.Cos(theta);

                for (var lon = 0; lon <= longitudeSegments; lon++)
                {
                    var u = (float)lon / longitudeSegments;
                    var phi = u * Mathf.PI * 2f;
                    vertices[vertex] = new Vector3(
                        radius * sinTheta * Mathf.Sin(phi),
                        radius * cosTheta,
                        radius * sinTheta * Mathf.Cos(phi)
                    );
                    uvs[vertex] = new Vector2(1f - u, 1f - v);
                    vertex++;
                }
            }

            var tri = 0;
            for (var lat = 0; lat < latitudeSegments; lat++)
            {
                for (var lon = 0; lon < longitudeSegments; lon++)
                {
                    var current = lat * (longitudeSegments + 1) + lon;
                    var next = current + longitudeSegments + 1;

                    triangles[tri++] = current;
                    triangles[tri++] = next + 1;
                    triangles[tri++] = next;
                    triangles[tri++] = current;
                    triangles[tri++] = current + 1;
                    triangles[tri++] = next + 1;
                }
            }

            mesh.vertices = vertices;
            mesh.uv = uvs;
            mesh.triangles = triangles;
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}

