// WP17-I1 native runtime. The ncnn PP-OCRv5 mobile detection and recognition
// pipeline is derived from the measured WP17-R2 core. This single source is
// compiled for Windows, Linux and Android; the C ABI below is the Dart boundary.
//
// Deliberate simplifications, recorded in docs/WP17_OCR_EVALUATION.md:
//   * Detection post-processing is the standard DB "unclip" for *axis-aligned*
//     boxes.  The reference ncnn example (examples/ppocrv5.cpp) expands boxes
//     heuristically instead and marks that as a known accuracy loss; we do not
//     reproduce that shortcut.  Rotated text lines are out of scope here, which
//     matches phone task screenshots.
//   * No OpenCV.  PNG decoding is stb_image, connected components are a small
//     union-find, cropping is a straight copy.  This keeps the exact same code
//     path on all three targets and avoids shipping opencv-mobile.
//   * Output order is the engine's own order. Task-draft assembly is separate.

#include "ocr_runtime.h"
#include "net.h"

#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_HDR
#include "stb_image.h"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#endif

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

static double now_ms()
{
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double, std::milli>(clock::now().time_since_epoch()).count();
}

static unsigned long long peak_rss_kb()
{
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        return (unsigned long long)(pmc.PeakWorkingSetSize / 1024ull);
    return 0;
#else
    FILE* fp = fopen("/proc/self/status", "r");
    if (!fp)
        return 0;
    char line[256];
    unsigned long long hwm = 0;
    while (fgets(line, sizeof(line), fp))
    {
        if (strncmp(line, "VmHWM:", 6) == 0)
        {
            sscanf(line + 6, "%llu", &hwm);
            break;
        }
    }
    fclose(fp);
    return hwm;
#endif
}

static std::string json_escape(const std::string& s)
{
    std::string o;
    o.reserve(s.size() + 8);
    for (size_t i = 0; i < s.size(); i++)
    {
        unsigned char c = (unsigned char)s[i];
        switch (c)
        {
        case '"': o += "\\\""; break;
        case '\\': o += "\\\\"; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        case '\t': o += "\\t"; break;
        default:
            if (c < 0x20)
            {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", c);
                o += buf;
            }
            else
            {
                o += (char)c;
            }
        }
    }
    return o;
}

static std::string read_file(const std::string& path)
{
    std::string out;
    FILE* fp = fopen(path.c_str(), "rb");
    if (!fp)
        return out;
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0)
        out.append(buf, n);
    fclose(fp);
    return out;
}

struct TextLine
{
    float x = 0, y = 0, w = 0, h = 0, score = 0;
    std::string text;
};

struct ImageResult
{
    std::string path;
    int width = 0, height = 0;
    int det_channel = 0;
    double decode_ms = 0, preprocess_ms = 0, det_ms = 0, rec_ms = 0, total_ms = 0;
    std::string error;
    std::vector<TextLine> lines;
};

// ---------------------------------------------------------------------------
// image decoding
// ---------------------------------------------------------------------------

struct Bitmap
{
    int w = 0, h = 0;
    // Own stb's allocation directly; converting RGB to BGR in place avoids
    // retaining a second full-size bitmap (36 MiB at the accepted pixel cap).
    std::unique_ptr<unsigned char, decltype(&stbi_image_free)> bgr{nullptr, stbi_image_free};
};

static bool load_png_bgr(const std::string& path, Bitmap& bm)
{
    int w = 0, h = 0, comp = 0;
    unsigned char* rgb = stbi_load(path.c_str(), &w, &h, &comp, 3);
    if (!rgb)
        return false;
    bm.w = w;
    bm.h = h;
    bm.bgr.reset(rgb);
    for (size_t i = 0, n = (size_t)w * h; i < n; i++)
        std::swap(rgb[i * 3], rgb[i * 3 + 2]);
    return true;
}

// ---------------------------------------------------------------------------
// engine interface
// ---------------------------------------------------------------------------

class Engine
{
public:
    virtual ~Engine() {}
    virtual bool load(const std::string& assets, const std::string& variant, std::string& err) = 0;
    virtual std::string name() const = 0;
    virtual std::string version() const = 0;
    virtual std::map<std::string, std::string> config() const = 0;
    virtual bool run(const Bitmap& bm, ImageResult& out, std::string& err) = 0;
};

// ---------------------------------------------------------------------------
// ncnn PP-OCRv5 mobile (CPU)
// ---------------------------------------------------------------------------

struct OcrOptions
{
    int threads = 4;
    int det_limit = 960;
    float det_thresh = 0.3f;
    float box_thresh = 0.6f;
    float unclip_ratio = 1.5f;
    int rec_max_width = 0; // 0 = keep native aspect (ncnn example behaviour)
    int min_area_px = 12;
};

class NcnnPpOcrv5 : public Engine
{
public:
    explicit NcnnPpOcrv5(const OcrOptions& opt) : opt_(opt) {}

    std::string name() const { return "ncnn-ppocrv5-mobile"; }
    std::string version() const { return NCNN_VERSION_STRING; }

    std::map<std::string, std::string> config() const
    {
        std::map<std::string, std::string> c;
        c["threads"] = tostr(opt_.threads);
        c["vulkan"] = "off";
        c["det_limit"] = tostr(opt_.det_limit);
        c["det_thresh"] = tostr(opt_.det_thresh);
        c["box_thresh"] = tostr(opt_.box_thresh);
        c["unclip_ratio"] = tostr(opt_.unclip_ratio);
        c["rec_max_width"] = tostr(opt_.rec_max_width);
        c["det_param"] = det_param_;
        c["rec_param"] = rec_param_;
        c["dict_chars"] = tostr((int)dict_.size());
        return c;
    }

    bool load(const std::string& assets, const std::string& variant, std::string& err)
    {
        (void)variant;
        det_param_ = assets + "/ncnn/PP_OCRv5_mobile_det.ncnn.param";
        std::string det_bin = assets + "/ncnn/PP_OCRv5_mobile_det.ncnn.bin";
        rec_param_ = assets + "/ncnn/PP_OCRv5_mobile_rec.ncnn.param";
        std::string rec_bin = assets + "/ncnn/PP_OCRv5_mobile_rec.ncnn.bin";
        std::string dict_path = assets + "/ncnn/ppocrv5_dict.txt";

        std::string d = read_file(dict_path);
        if (d.empty())
        {
            err = "cannot read dict: " + dict_path;
            return false;
        }
        // The dict file is one character (possibly multibyte) per line, plus a
        // leading blank line that maps to CTC blank.
        size_t pos = 0;
        while (pos <= d.size())
        {
            size_t nl = d.find('\n', pos);
            std::string line = d.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
            while (!line.empty() && (line.back() == '\r' || line.back() == ' '))
                line.pop_back();
            dict_.push_back(line);
            if (nl == std::string::npos)
                break;
            pos = nl + 1;
        }
        if (dict_.size() < 10)
        {
            err = "dict too small: " + dict_path;
            return false;
        }

        // CPU only: Vulkan would turn the GPU into a hard device requirement.
        det_.opt.use_vulkan_compute = false;
        rec_.opt.use_vulkan_compute = false;
        det_.opt.num_threads = opt_.threads;
        rec_.opt.num_threads = opt_.threads;
        // ncnn's Net-owned pools retain freed detection blobs/workspaces and
        // oversized buffers across recognition widths until destruction. Direct
        // allocation releases dead blobs/workspaces in lightmode, preserving
        // the model, kernels and output while bounding a reused session.
        det_.opt.use_local_pool_allocator = false;
        rec_.opt.use_local_pool_allocator = false;
        // opt.lightmode stays at ncnn's default (true) so intermediate blobs are
        // recycled; keeping them alive multiplies peak RSS for no benefit.

        if (det_.load_param(det_param_.c_str()) != 0 || det_.load_model(det_bin.c_str()) != 0)
        {
            err = "cannot load det model " + det_param_;
            return false;
        }
        if (rec_.load_param(rec_param_.c_str()) != 0 || rec_.load_model(rec_bin.c_str()) != 0)
        {
            err = "cannot load rec model " + rec_param_;
            return false;
        }
        return true;
    }

    bool run(const Bitmap& bm, ImageResult& out, std::string& err)
    {
        std::vector<TextLine> boxes;
        double t0 = now_ms();
        if (!detect(bm, boxes, err))
            return false;
        out.det_ms = now_ms() - t0;

        t0 = now_ms();
        for (size_t i = 0; i < boxes.size(); i++)
        {
            std::string text;
            float score = 0;
            if (!recognize(bm, boxes[i], text, score))
                continue;
            boxes[i].text = text;
            boxes[i].score = score;
        }
        out.rec_ms = now_ms() - t0;
        out.lines.swap(boxes);
        return true;
    }

private:
    static std::string tostr(int v)
    {
        char b[32];
        snprintf(b, sizeof(b), "%d", v);
        return b;
    }
    static std::string tostr(float v)
    {
        char b[32];
        snprintf(b, sizeof(b), "%.4f", v);
        return b;
    }

    bool detect(const Bitmap& bm, std::vector<TextLine>& out, std::string& err)
    {
        const int target_stride = 32;
        int img_w = bm.w, img_h = bm.h;
        int w = img_w, h = img_h;
        float scale = 1.f;
        if (std::max(w, h) > opt_.det_limit)
        {
            if (w > h)
            {
                scale = (float)opt_.det_limit / w;
                w = opt_.det_limit;
                h = (int)(h * scale);
            }
            else
            {
                scale = (float)opt_.det_limit / h;
                h = opt_.det_limit;
                w = (int)(w * scale);
            }
        }
        if (w < 1) w = 1;
        if (h < 1) h = 1;

        ncnn::Mat in = ncnn::Mat::from_pixels_resize(bm.bgr.get(), ncnn::Mat::PIXEL_BGR, img_w, img_h, w, h);
        if (in.empty())
        {
            err = "from_pixels_resize failed";
            return false;
        }
        int wpad = (w + target_stride - 1) / target_stride * target_stride - w;
        int hpad = (h + target_stride - 1) / target_stride * target_stride - h;
        ncnn::Mat in_pad;
        ncnn::copy_make_border(in, in_pad, hpad / 2, hpad - hpad / 2, wpad / 2, wpad - wpad / 2, ncnn::BORDER_CONSTANT, 114.f);

        const float mean_vals[3] = {0.485f * 255.f, 0.456f * 255.f, 0.406f * 255.f};
        const float norm_vals[3] = {1 / 0.229f / 255.f, 1 / 0.224f / 255.f, 1 / 0.225f / 255.f};
        in_pad.substract_mean_normalize(mean_vals, norm_vals);

        ncnn::Extractor ex = det_.create_extractor();
        ex.input("in0", in_pad);
        ncnn::Mat outmat;
        if (ex.extract("out0", outmat) != 0)
        {
            err = "det extract failed";
            return false;
        }

        const float denorm_vals[1] = {255.f};
        outmat.substract_mean_normalize(0, denorm_vals);

        const int mw = outmat.w, mh = outmat.h;
        if (mw <= 0 || mh <= 0 || outmat.elempack != 1)
        {
            err = "unexpected det output shape";
            return false;
        }
        std::vector<unsigned char> prob((size_t)mw * mh);
        {
            // outmat is single channel float; convert to uint8 exactly like
            // ncnn's to_pixels(PIXEL_GRAY) does after *255 denormalisation.
            for (int y = 0; y < mh; y++)
            {
                const float* p = outmat.row(y);
                for (int x = 0; x < mw; x++)
                {
                    float v = p[x];
                    v = v < 0.f ? 0.f : (v > 255.f ? 255.f : v);
                    prob[(size_t)y * mw + x] = (unsigned char)(v + 0.5f);
                }
            }
        }

        std::vector<unsigned char> mask((size_t)mw * mh, 0);
        const unsigned char thr = (unsigned char)(opt_.det_thresh * 255.f + 0.5f);
        for (size_t i = 0; i < mask.size(); i++)
            mask[i] = prob[i] >= thr ? 1 : 0;

        // ---- connected components (8-neighbourhood, iterative flood fill) ----
        std::vector<int> label((size_t)mw * mh, 0);
        std::vector<int> stack;
        int next_label = 0;
        struct Comp
        {
            int x0, y0, x1, y1;
            double sum;
            int area;
        };
        std::vector<Comp> comps;

        for (int y = 0; y < mh; y++)
        {
            for (int x = 0; x < mw; x++)
            {
                size_t idx = (size_t)y * mw + x;
                if (!mask[idx] || label[idx])
                    continue;
                next_label++;
                Comp c;
                c.x0 = c.x1 = x;
                c.y0 = c.y1 = y;
                c.sum = 0;
                c.area = 0;
                stack.clear();
                stack.push_back((int)idx);
                label[idx] = next_label;
                while (!stack.empty())
                {
                    int cur = stack.back();
                    stack.pop_back();
                    int cy = cur / mw, cx = cur % mw;
                    c.sum += prob[cur];
                    c.area++;
                    if (cx < c.x0) c.x0 = cx;
                    if (cx > c.x1) c.x1 = cx;
                    if (cy < c.y0) c.y0 = cy;
                    if (cy > c.y1) c.y1 = cy;
                    for (int dy = -1; dy <= 1; dy++)
                    {
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            if (!dx && !dy)
                                continue;
                            int nx = cx + dx, ny = cy + dy;
                            if (nx < 0 || ny < 0 || nx >= mw || ny >= mh)
                                continue;
                            size_t ni = (size_t)ny * mw + nx;
                            if (!mask[ni] || label[ni])
                                continue;
                            label[ni] = next_label;
                            stack.push_back((int)ni);
                        }
                    }
                }
                comps.push_back(c);
            }
        }

        const float min_size = 3.f * scale;
        for (size_t i = 0; i < comps.size(); i++)
        {
            const Comp& c = comps[i];
            if (c.area <= 2)
                continue;
            double score = (c.sum / c.area) / 255.0;
            if (score < opt_.box_thresh)
                continue;
            float bw = (float)(c.x1 - c.x0 + 1);
            float bh = (float)(c.y1 - c.y0 + 1);
            if (std::max(bw, bh) < min_size)
                continue;

            // DB unclip for an axis-aligned rectangle:
            //   offset = area * ratio / perimeter
            float off = (bw * bh) * opt_.unclip_ratio / (2.f * (bw + bh));
            float x0 = (float)c.x0 - off;
            float y0 = (float)c.y0 - off;
            float x1 = (float)c.x1 + 1.f + off;
            float y1 = (float)c.y1 + 1.f + off;

            // map back from padded+scaled det space to original pixels
            x0 = (x0 - wpad / 2.f) / scale;
            y0 = (y0 - hpad / 2.f) / scale;
            x1 = (x1 - wpad / 2.f) / scale;
            y1 = (y1 - hpad / 2.f) / scale;

            TextLine ln;
            ln.x = x0;
            ln.y = y0;
            ln.w = x1 - x0;
            ln.h = y1 - y0;
            ln.score = (float)score;
            out.push_back(ln);
        }
        return true;
    }

    bool recognize(const Bitmap& bm, const TextLine& box, std::string& text, float& score)
    {
        int x0 = (int)std::floor(box.x);
        int y0 = (int)std::floor(box.y);
        int x1 = (int)std::ceil(box.x + box.w);
        int y1 = (int)std::ceil(box.y + box.h);
        x0 = std::max(0, std::min(x0, bm.w - 1));
        y0 = std::max(0, std::min(y0, bm.h - 1));
        x1 = std::max(x0 + 1, std::min(x1, bm.w));
        y1 = std::max(y0 + 1, std::min(y1, bm.h));
        int cw = x1 - x0;
        int ch = y1 - y0;
        if (cw < 2 || ch < 2)
            return false;

        const int target_h = 48;
        int target_w = (int)std::round((float)cw * target_h / ch);
        if (target_w < 8)
            target_w = 8;
        if (opt_.rec_max_width > 0 && target_w > opt_.rec_max_width)
            target_w = opt_.rec_max_width;

        std::vector<unsigned char> crop((size_t)cw * ch * 3);
        for (int y = 0; y < ch; y++)
        {
            const unsigned char* src = bm.bgr.get() + ((size_t)(y0 + y) * bm.w + x0) * 3;
            memcpy(crop.data() + (size_t)y * cw * 3, src, (size_t)cw * 3);
        }

        ncnn::Mat in = ncnn::Mat::from_pixels_resize(crop.data(), ncnn::Mat::PIXEL_BGR, cw, ch, target_w, target_h);
        const float mean_vals[3] = {127.5f, 127.5f, 127.5f};
        const float norm_vals[3] = {1.f / 127.5f, 1.f / 127.5f, 1.f / 127.5f};
        in.substract_mean_normalize(mean_vals, norm_vals);

        ncnn::Extractor ex = rec_.create_extractor();
        ex.input("in0", in);
        ncnn::Mat outmat;
        if (ex.extract("out0", outmat) != 0)
            return false;

        // outmat: (num_tokens) x (num_classes); class 0 is CTC blank.
        int last = 0;
        double sum = 0;
        int n = 0;
        for (int i = 0; i < outmat.h; i++)
        {
            const float* p = outmat.row(i);
            int idx = 0;
            float best = -1e9f;
            for (int j = 0; j < outmat.w; j++)
            {
                if (p[j] > best)
                {
                    best = p[j];
                    idx = j;
                }
            }
            if (idx == last)
                continue;
            last = idx;
            if (idx <= 0)
                continue;
            int di = idx - 1;
            if (di < (int)dict_.size())
                text += dict_[di];
            sum += best;
            n++;
        }
        score = n ? (float)(sum / n) : 0.f;
        return true;
    }

    OcrOptions opt_;
    ncnn::Net det_;
    ncnn::Net rec_;
    std::vector<std::string> dict_;
    std::string det_param_, rec_param_;
};

struct RuntimeSession
{
    explicit RuntimeSession(const OcrOptions& options) : engine(options) {}
    NcnnPpOcrv5 engine;
    std::string error;
    bool ready = false;
};

static char* json_result(const ImageResult& result)
{
    std::string body = "{\"schema\":\"wp17-i1-ocr/1\",\"width\":" + std::to_string(result.width)
        + ",\"height\":" + std::to_string(result.height)
        + ",\"error\":\"" + json_escape(result.error) + "\",\"lines\":[";
    for (size_t i = 0; i < result.lines.size(); ++i)
    {
        const TextLine& line = result.lines[i];
        char nums[192];
        snprintf(nums, sizeof(nums), "\"box\":[%.2f,%.2f,%.2f,%.2f],\"score\":%.4f",
                 line.x, line.y, line.w, line.h, line.score);
        if (i)
            body += ',';
        body += "{\"text\":\"" + json_escape(line.text) + "\"," + nums + '}';
    }
    body += "]}";
    char* output = static_cast<char*>(malloc(body.size() + 1));
    if (!output)
        return nullptr;
    memcpy(output, body.c_str(), body.size() + 1);
    return output;
}

extern "C" MF_OCR_EXPORT void* mf_ocr_create(const char* assets, int threads)
{
    try
    {
        OcrOptions options;
        options.threads = std::max(1, std::min(threads, 4));
        std::unique_ptr<RuntimeSession> session(new RuntimeSession(options));
        session->ready = session->engine.load(assets ? assets : "", "", session->error);
        return session.release();
    }
    catch (...)
    {
        return nullptr;
    }
}

extern "C" MF_OCR_EXPORT char* mf_ocr_run_file(void* opaque, const char* image_path)
{
    ImageResult result;
    try
    {
        RuntimeSession* session = static_cast<RuntimeSession*>(opaque);
        if (!session)
            result.error = "native OCR session allocation failed";
        else if (!session->ready)
            result.error = session->error.empty() ? "model load failed" : session->error;
        else if (!image_path || !*image_path)
            result.error = "image path is empty";
        else
        {
            FILE* fp = fopen(image_path, "rb");
            if (!fp)
                result.error = "cannot open image";
            else
            {
                const bool ok = fseek(fp, 0, SEEK_END) == 0;
                const long bytes = ok ? ftell(fp) : -1;
                fclose(fp);
                if (bytes <= 0 || bytes > 16 * 1024 * 1024)
                    result.error = "image file exceeds 16 MiB or is empty";
                else
                {
                    int w = 0, h = 0, components = 0;
                    if (!stbi_info(image_path, &w, &h, &components))
                        result.error = "PNG header decode failed";
                    else if (w <= 0 || h <= 0 || w > 4096 || h > 8192 ||
                             static_cast<int64_t>(w) * h > 12 * 1024 * 1024)
                        result.error = "image dimensions exceed OCR limit";
                    else
                    {
                        Bitmap bitmap;
                        if (!load_png_bgr(image_path, bitmap))
                            result.error = "PNG decode failed";
                        else
                        {
                            result.width = bitmap.w;
                            result.height = bitmap.h;
                            session->engine.run(bitmap, result, result.error);
                        }
                    }
                }
            }
        }
    }
    catch (...)
    {
        result.error = "unexpected native OCR failure";
        result.lines.clear();
    }
    try
    {
        return json_result(result);
    }
    catch (...)
    {
        return nullptr;
    }
}

extern "C" MF_OCR_EXPORT void mf_ocr_destroy(void* opaque)
{
    delete static_cast<RuntimeSession*>(opaque);
}

extern "C" MF_OCR_EXPORT void mf_ocr_free(char* result)
{
    free(result);
}

