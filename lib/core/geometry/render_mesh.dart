import 'dart:typed_data';

/// A triangle surface mesh for visualization: shared vertex positions plus
/// triangle index triples.
///
/// Both solver paths in [ModalAnalysisResult] produce one of these directly
/// from their own solve mesh -- the native FEM path returns its tetrahedral
/// mesh's boundary surface (smooth, vertices shared between adjacent
/// triangles), the Dart FDM fallback returns its voxel grid's boundary
/// faces (flat-shaded, one quad's four corners are not shared with
/// neighbouring quads) -- so the UI never needs to know which solver ran.
class RenderMesh {
  RenderMesh({required this.positions, required this.triangles});

  /// Vertex positions, interleaved xyz (length = 3 * [nodeCount]).
  final Float64List positions;

  /// Triangle vertex indices (length = 3 * [triangleCount]).
  final Int32List triangles;

  int get nodeCount => positions.length ~/ 3;
  int get triangleCount => triangles.length ~/ 3;

  double x(int node) => positions[node * 3];
  double y(int node) => positions[node * 3 + 1];
  double z(int node) => positions[node * 3 + 2];
}
