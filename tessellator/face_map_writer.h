#pragma once

#include <RWGltf_CafWriter.hxx>
#include <RWGltf_GltfFace.hxx>
#include <TopoDS_Face.hxx>

#include <vector>

// One B-rep face inside one glTF primitive.
struct FaceRange
{
    Handle(RWGltf_GltfFace) primitive; // the merged primitive the face was written into
    int faceId = 0;                    // B-rep face index, in the order the writer visits faces
    int firstTriangle = 0;             // first triangle of this face inside the primitive
    int triangleCount = 0;
};

// RWGltf_CafWriter that records where each B-rep face's triangles end up.
//
// The writer calls saveIndices() once per face, in output order, while it appends that
// face's triangles to the current primitive. Recording here (instead of re-walking the
// document ourselves) guarantees the face map matches the GLB exactly.
class FaceMapWriter : public RWGltf_CafWriter
{
public:
    using RWGltf_CafWriter::RWGltf_CafWriter;

    const std::vector<FaceRange>& FaceRanges() const { return myFaceRanges; }

protected:
    void saveIndices(RWGltf_GltfFace& theGltfFace,
                     std::ostream& theBinFile,
                     const RWMesh_FaceIterator& theFaceIter,
                     Standard_Integer& theAccessorNb) override;

private:
    std::vector<FaceRange> myFaceRanges;
};
