// tessellator: STEP in -> GLB (+ optional JSON metadata with a B-rep face map) out.
//
// Exit codes: 0 ok, 1 read/transfer error, 2 usage error, 3 mesh/export error.
// Errors go to stderr so the Rails job can store them in parts.error_message.

#include "face_map_writer.h"

#include <BRepBndLib.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <Bnd_Box.hxx>
#include <Message_ProgressRange.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <Standard_Failure.hxx>
#include <Standard_Version.hxx>
#include <TColStd_IndexedDataMapOfStringString.hxx>
#include <TDocStd_Document.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace
{

enum ExitCode
{
    kOk = 0,
    kReadError = 1,
    kUsageError = 2,
    kExportError = 3,
};

constexpr const char* kUsage =
    "Usage: tessellator <in.step> <out.glb> [--rel-deflection 0.01] [--angular 0.1] [--meta out.json]\n"
    "  --rel-deflection  linear deflection as a fraction of the bounding-box diagonal (default 0.01)\n"
    "  --angular         angular deflection in radians (default 0.1)\n"
    "  --meta            write JSON metadata (bbox, counts, timings, face map) to this file\n";

struct Options
{
    std::string input;
    std::string output;
    std::string meta;
    double relDeflection = 0.01;
    double angularDeflection = 0.1;
};

bool parsePositive(const char* text, double& value)
{
    char* end = nullptr;
    value = std::strtod(text, &end);
    return end != text && *end == '\0' && std::isfinite(value) && value > 0.0;
}

// Returns an empty string on success, otherwise the usage error.
std::string parseArgs(int argc, char** argv, Options& options)
{
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i)
    {
        const std::string arg = argv[i];
        const bool hasValue = i + 1 < argc;
        if (arg == "--rel-deflection" || arg == "--angular")
        {
            double& target = arg == "--angular" ? options.angularDeflection : options.relDeflection;
            if (!hasValue || !parsePositive(argv[++i], target))
                return arg + " needs a positive number";
        }
        else if (arg == "--meta")
        {
            if (!hasValue) return "--meta needs a file path";
            options.meta = argv[++i];
        }
        else if (arg.rfind("--", 0) == 0)
        {
            return "unknown option " + arg;
        }
        else
        {
            positional.push_back(arg);
        }
    }
    if (positional.size() != 2) return "expected <in.step> and <out.glb>";
    options.input = positional[0];
    options.output = positional[1];
    return {};
}

using Clock = std::chrono::steady_clock;

double msSince(Clock::time_point start)
{
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

std::string jsonString(const std::string& text)
{
    std::ostringstream out;
    out << '"';
    for (const unsigned char c : text)
    {
        switch (c)
        {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (c < 0x20) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c) << std::dec;
                else out << c;
        }
    }
    out << '"';
    return out.str();
}

std::string jsonVec3(const gp_XYZ& v)
{
    std::ostringstream out;
    out << std::setprecision(9) << '[' << v.X() << ", " << v.Y() << ", " << v.Z() << ']';
    return out.str();
}

// Faces grouped by the glTF primitive they were merged into, in output order.
struct PrimitiveFaces
{
    Handle(RWGltf_GltfFace) primitive;
    std::vector<const FaceRange*> faces;
};

std::vector<PrimitiveFaces> groupByPrimitive(const std::vector<FaceRange>& ranges)
{
    std::vector<PrimitiveFaces> groups;
    std::map<const RWGltf_GltfFace*, size_t> indexOf;
    for (const FaceRange& range : ranges)
    {
        auto [it, inserted] = indexOf.emplace(range.primitive.get(), groups.size());
        if (inserted) groups.push_back({range.primitive, {}});
        groups[it->second].faces.push_back(&range);
    }
    return groups;
}

struct Timings
{
    double read = 0, mesh = 0, exportGlb = 0, total = 0;
};

int64_t countTriangles(const std::vector<FaceRange>& ranges)
{
    int64_t count = 0;
    for (const FaceRange& range : ranges) count += range.triangleCount;
    return count;
}

bool writeMeta(const Options& options,
               const gp_XYZ& bboxMin,
               const gp_XYZ& bboxMax,
               double linearDeflectionM,
               const std::vector<FaceRange>& ranges,
               const Timings& timings)
{
    std::ofstream out(options.meta);
    if (!out) return false;

    out << std::setprecision(9);
    out << "{\n";
    out << "  \"occt_version\": " << jsonString(OCC_VERSION_COMPLETE) << ",\n";
    out << "  \"input\": " << jsonString(options.input) << ",\n";
    out << "  \"units\": \"m\",\n";
    out << "  \"up_axis\": \"Y\",\n";
    out << "  \"settings\": {\"rel_deflection\": " << options.relDeflection
        << ", \"linear_deflection_m\": " << linearDeflectionM
        << ", \"angular_deflection_rad\": " << options.angularDeflection << "},\n";
    out << "  \"bbox\": {\"min\": " << jsonVec3(bboxMin) << ", \"max\": " << jsonVec3(bboxMax) << "},\n";
    out << "  \"triangle_count\": " << countTriangles(ranges) << ",\n";
    out << "  \"face_count\": " << ranges.size() << ",\n";
    out << std::fixed << std::setprecision(1);
    out << "  \"timings_ms\": {\"read\": " << timings.read << ", \"mesh\": " << timings.mesh
        << ", \"export\": " << timings.exportGlb << ", \"total\": " << timings.total << "},\n";
    out << std::defaultfloat;

    // face_map.primitives[i].indices_accessor is the glTF accessor id of that primitive's
    // index buffer (meshes[m].primitives[p].indices in the GLB). Each face lists its triangle
    // range inside that primitive: triangles [first, first + count).
    out << "  \"face_map\": {\n    \"primitives\": [";
    const std::vector<PrimitiveFaces> groups = groupByPrimitive(ranges);
    for (size_t g = 0; g < groups.size(); ++g)
    {
        const PrimitiveFaces& group = groups[g];
        out << (g ? ",\n" : "\n");
        out << "      {\"indices_accessor\": " << group.primitive->Indices.Id
            << ", \"triangle_count\": " << group.primitive->Indices.Count / 3 << ", \"faces\": [";
        for (size_t f = 0; f < group.faces.size(); ++f)
        {
            const FaceRange& face = *group.faces[f];
            out << (f ? ", " : "") << "{\"id\": " << face.faceId << ", \"first\": " << face.firstTriangle
                << ", \"count\": " << face.triangleCount << "}";
        }
        out << "]}";
    }
    out << "\n    ]\n  }\n}\n";
    return static_cast<bool>(out);
}

} // namespace

int main(int argc, char** argv)
{
    Options options;
    if (argc == 2 && (std::string(argv[1]) == "-h" || std::string(argv[1]) == "--help"))
    {
        std::cout << kUsage;
        return kOk;
    }
    if (const std::string error = parseArgs(argc, argv, options); !error.empty())
    {
        std::cerr << "tessellator: " << error << "\n" << kUsage;
        return kUsageError;
    }

    const auto totalStart = Clock::now();
    Timings timings;

    // 1. Read the STEP file into an XCAF document (shapes, names, colors, assembly structure).
    Handle(TDocStd_Document) document;
    TDF_LabelSequence roots;
    try
    {
        const auto start = Clock::now();
        XCAFApp_Application::GetApplication()->NewDocument("MDTV-XCAF", document);
        STEPCAFControl_Reader reader;
        reader.SetColorMode(Standard_True);
        reader.SetNameMode(Standard_True);
        if (reader.ReadFile(options.input.c_str()) != IFSelect_RetDone)
        {
            std::cerr << "tessellator: could not read STEP file " << options.input << "\n";
            return kReadError;
        }
        if (!reader.Transfer(document))
        {
            std::cerr << "tessellator: STEP transfer failed for " << options.input << "\n";
            return kReadError;
        }
        XCAFDoc_DocumentTool::ShapeTool(document->Main())->GetFreeShapes(roots);
        timings.read = msSince(start);
    }
    catch (const Standard_Failure& failure)
    {
        std::cerr << "tessellator: OCCT error while reading: " << failure.GetMessageString() << "\n";
        return kReadError;
    }

    // 2. Mesh. One linear deflection for the whole document, relative to its bounding box,
    //    so every part gets the same absolute tolerance.
    Bnd_Box modelBox;
    double linearDeflectionMm = 0.0;
    try
    {
        const auto start = Clock::now();
        for (Standard_Integer i = 1; i <= roots.Length(); ++i)
            BRepBndLib::Add(XCAFDoc_ShapeTool::GetShape(roots.Value(i)), modelBox);
        if (modelBox.IsVoid())
        {
            std::cerr << "tessellator: the file has no geometry\n";
            return kReadError;
        }
        linearDeflectionMm = options.relDeflection * std::sqrt(modelBox.SquareExtent());

        modelBox.SetVoid(); // recomputed below from the mesh, without tolerance padding
        for (Standard_Integer i = 1; i <= roots.Length(); ++i)
        {
            const TopoDS_Shape shape = XCAFDoc_ShapeTool::GetShape(roots.Value(i));
            BRepMesh_IncrementalMesh mesher(shape, linearDeflectionMm, Standard_False,
                                            options.angularDeflection, Standard_True);
            if (!mesher.IsDone()) std::cerr << "tessellator: warning: mesher did not finish root " << i << "\n";

            BRepBndLib::AddOptimal(shape, modelBox, Standard_True, Standard_False);
        }
        timings.mesh = msSince(start);
    }
    catch (const Standard_Failure& failure)
    {
        std::cerr << "tessellator: OCCT error while meshing: " << failure.GetMessageString() << "\n";
        return kExportError;
    }

    // 3. Write the GLB. OCCT is mm and Z-up; glTF is meters and Y-up.
    //    Normals: BRepMesh stores none, and the writer (RWMesh_FaceIterator) computes them from
    //    the exact surface at each node's UV, flipped for reversed faces. Precomputing them with
    //    BRepLib::EnsureNormalConsistency is wrong here: it stores raw surface normals, and the
    //    writer then exports them unflipped on reversed faces.
    FaceMapWriter writer(options.output.c_str(), Standard_True);
    writer.ChangeCoordinateSystemConverter().SetInputLengthUnit(0.001);
    writer.ChangeCoordinateSystemConverter().SetInputCoordinateSystem(RWMesh_CoordinateSystem_Zup);
    writer.SetMergeFaces(true); // one primitive per part instead of one per face
    try
    {
        const auto start = Clock::now();
        TColStd_IndexedDataMapOfStringString fileInfo;
        if (!writer.Perform(document, fileInfo, Message_ProgressRange()))
        {
            std::cerr << "tessellator: could not write GLB " << options.output << "\n";
            return kExportError;
        }
        timings.exportGlb = msSince(start);
    }
    catch (const Standard_Failure& failure)
    {
        std::cerr << "tessellator: OCCT error while writing GLB: " << failure.GetMessageString() << "\n";
        return kExportError;
    }

    const std::vector<FaceRange>& ranges = writer.FaceRanges();
    if (ranges.empty())
    {
        std::cerr << "tessellator: no triangles were produced\n";
        return kExportError;
    }

    // Bounding box in glTF space: transform all 8 corners with the writer's own converter.
    gp_XYZ bboxMin(1e300, 1e300, 1e300), bboxMax(-1e300, -1e300, -1e300);
    {
        double x0, y0, z0, x1, y1, z1;
        modelBox.Get(x0, y0, z0, x1, y1, z1);
        for (int corner = 0; corner < 8; ++corner)
        {
            gp_XYZ p(corner & 1 ? x1 : x0, corner & 2 ? y1 : y0, corner & 4 ? z1 : z0);
            writer.CoordinateSystemConverter().TransformPosition(p);
            bboxMin.SetCoord(std::min(bboxMin.X(), p.X()), std::min(bboxMin.Y(), p.Y()), std::min(bboxMin.Z(), p.Z()));
            bboxMax.SetCoord(std::max(bboxMax.X(), p.X()), std::max(bboxMax.Y(), p.Y()), std::max(bboxMax.Z(), p.Z()));
        }
    }

    timings.total = msSince(totalStart);

    if (!options.meta.empty() &&
        !writeMeta(options, bboxMin, bboxMax, linearDeflectionMm * 0.001, ranges, timings))
    {
        std::cerr << "tessellator: could not write metadata " << options.meta << "\n";
        return kExportError;
    }

    std::cout << "Wrote " << options.output << ": " << ranges.size() << " faces, " << countTriangles(ranges)
              << " triangles in " << std::fixed << std::setprecision(0) << timings.total << " ms\n";
    return kOk;
}
