#include "face_map_writer.h"

void FaceMapWriter::saveIndices(RWGltf_GltfFace& theGltfFace,
                                std::ostream& theBinFile,
                                const RWMesh_FaceIterator& theFaceIter,
                                Standard_Integer& theAccessorNb)
{
    // Indices.Count grows by 3 per triangle as faces are merged into this primitive.
    const int64_t indicesBefore = theGltfFace.Indices.Count;
    RWGltf_CafWriter::saveIndices(theGltfFace, theBinFile, theFaceIter, theAccessorNb);
    const int64_t indicesAfter = theGltfFace.Indices.Count;

    FaceRange range;
    range.primitive = &theGltfFace; // Standard_Transient: the handle keeps it alive
    range.faceId = static_cast<int>(myFaceRanges.size());
    range.firstTriangle = static_cast<int>(indicesBefore / 3);
    range.triangleCount = static_cast<int>((indicesAfter - indicesBefore) / 3);
    myFaceRanges.push_back(range);
}
