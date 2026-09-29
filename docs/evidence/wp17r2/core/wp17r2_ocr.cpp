// WP17-R2 OCR processing core.
//
// One binary, one processing pipeline, three platforms (Windows / Linux /
// Android).  Two interchangeable engines:
//
//   ncnn      PP-OCRv5 mobile det + rec (ncnn, CPU only, no Vulkan)
//   tesseract Tesseract 5 + tessdata_fast, C API
//
// Deliberate simplifications, all recorded in docs/WP17_OCR_EVALUATION.md:
//   * Detection post-processing is the standard DB "unclip" for *axis-aligned*
//     boxes.  The reference ncnn example (examples/ppocrv5.cpp) expands boxes
//     heuristically instead and marks that as a known accuracy loss; we do not
//     reproduce that shortcut.  Rotated text lines are out of scope here, which
//     matches phone task screenshots.
//   * No OpenCV.  PNG decoding is stb_image, connected components are a small
//     union-find, cropping is a straight copy.  This keeps the exact same code
//     path on all three targets and avoids shipping opencv-mobile.
//   * Output order is the engine's own order (raster order for our connected
//     components, Tesseract reading order for tesseract).  Row/column assembly
//     into a task draft is the adapter's job and is scored separately.
//
// Build: see core/CMakeLists.txt
// Usage: wp17r2_ocr --engine ncnn --assets DIR --out r.json img1.png img2.png

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
#include <string>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_HDR
#include "stb_image.h"

#ifdef WP17R2_WITH_TESSERACT
#include "tess_c_api.h"
#endif

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
    std::vector<unsigned char> bgr; // 3 bytes per pixel, BGR, row-major
};

static bool load_png_bgr(const std::string& path, Bitmap& bm)
{
    int w = 0, h = 0, comp = 0;
    unsigned char* rgb = stbi_load(path.c_str(), &w, &h, &comp, 3);
    if (!rgb)
        return false;
    bm.w = w;
    bm.h = h;
    bm.bgr.resize((size_t)w * h * 3);
    for (size_t i = 0, n = (size_t)w * h; i < n; i++)
    {
        bm.bgr[i * 3 + 0] = rgb[i * 3 + 2];
        bm.bgr[i * 3 + 1] = rgb[i * 3 + 1];
        bm.bgr[i * 3 + 2] = rgb[i * 3 + 0];
    }
    stbi_image_free(rgb);
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

        ncnn::Mat in = ncnn::Mat::from_pixels_resize(bm.bgr.data(), ncnn::Mat::PIXEL_BGR, img_w, img_h, w, h);
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
            const unsigned char* src = bm.bgr.data() + ((size_t)(y0 + y) * bm.w + x0) * 3;
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

#ifdef WP17R2_WITH_TESSERACT
// ---------------------------------------------------------------------------
// Tesseract 5 (C API)
// ---------------------------------------------------------------------------

class TessOcr : public Engine
{
public:
    TessOcr(const std::string& langs, int psm, const std::string& tessdata) : langs_(langs), psm_(psm), tessdata_(tessdata) {}

    ~TessOcr()
    {
        if (api_)
            TessBaseAPIDelete(api_);
    }

    std::string name() const { return "tesseract5-tessdata_fast"; }
    std::string version() const
    {
        const char* v = TessVersion();
        return v ? v : "";
    }

    std::map<std::string, std::string> config() const
    {
        std::map<std::string, std::string> c;
        c["langs"] = langs_;
        c["psm"] = std::to_string(psm_);
        c["tessdata"] = tessdata_;
        c["oem"] = "default(LSTM)";
        c["user_defined_dpi"] = "96";
        return c;
    }

    bool load(const std::string& assets, const std::string& variant, std::string& err)
    {
        (void)assets;
        (void)variant;
        api_ = TessBaseAPICreate();
        if (!api_)
        {
            err = "TessBaseAPICreate failed";
            return false;
        }
        if (TessBaseAPIInit3(api_, tessdata_.c_str(), langs_.c_str()) != 0)
        {
            err = "TessBaseAPIInit3 failed for langs=" + langs_ + " tessdata=" + tessdata_;
            return false;
        }
        TessBaseAPISetPageSegMode(api_, (TessPageSegMode)psm_);
        TessBaseAPISetVariable(api_, "user_defined_dpi", "96");
        return true;
    }

    bool run(const Bitmap& bm, ImageResult& out, std::string& err)
    {
        // Tesseract wants RGB.
        std::vector<unsigned char> rgb((size_t)bm.w * bm.h * 3);
        for (size_t i = 0, n = (size_t)bm.w * bm.h; i < n; i++)
        {
            rgb[i * 3 + 0] = bm.bgr[i * 3 + 2];
            rgb[i * 3 + 1] = bm.bgr[i * 3 + 1];
            rgb[i * 3 + 2] = bm.bgr[i * 3 + 0];
        }
        TessBaseAPISetImage(api_, rgb.data(), bm.w, bm.h, 3, bm.w * 3);
        double t0 = now_ms();
        if (TessBaseAPIRecognize(api_, nullptr) != 0)
        {
            err = "TessBaseAPIRecognize failed";
            return false;
        }
        // Tesseract has no separable detection/recognition stage; the whole cost
        // is reported as det_ms so the field is never silently zero.
        out.det_ms = now_ms() - t0;
        out.rec_ms = 0;

        TessResultIterator* it = TessBaseAPIGetIterator(api_);
        if (!it)
            return true;
        do
        {
            char* txt = TessResultIteratorGetUTF8Text(it, RIL_TEXTLINE);
            if (!txt)
                continue;
            std::string s = txt;
            TessDeleteText(txt);
            while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' '))
                s.pop_back();
            if (s.empty())
                continue;
            int x0, y0, x1, y1;
            if (!TessPageIteratorBoundingBox((TessPageIterator*)it, RIL_TEXTLINE, &x0, &y0, &x1, &y1))
                continue;
            TextLine ln;
            ln.x = (float)x0;
            ln.y = (float)y0;
            ln.w = (float)(x1 - x0);
            ln.h = (float)(y1 - y0);
            ln.score = TessResultIteratorConfidence(it, RIL_TEXTLINE) / 100.f;
            ln.text = s;
            out.lines.push_back(ln);
        } while (TessResultIteratorNext(it, RIL_TEXTLINE));
        TessResultIteratorDelete(it);
        return true;
    }

private:
    std::string langs_, tessdata_;
    int psm_;
    TessBaseAPI* api_ = nullptr;
};
#endif // WP17R2_WITH_TESSERACT

// ---------------------------------------------------------------------------
// driver
// ---------------------------------------------------------------------------

static void usage(const char* argv0)
{
    fprintf(stderr,
            "usage: %s --engine <ncnn|tesseract> --assets <dir> --out <file.json>\n"
            "          [--tessdata <dir>] [--tess-langs chi_sim+eng+jpn] [--tess-psm 3]\n"
            "          [--threads N] [--det-limit 960] [--rec-max-width 0]\n"
            "          [--unclip-ratio 1.5] [--box-thresh 0.6] [--det-thresh 0.3]\n"
            "          [--variant tag] [--quiet]\n"
            "          image.png [image.png ...]\n",
            argv0);
}

int main(int argc, char** argv)
{
    std::string engine_name, assets, out_path, tessdata, tess_langs = "chi_sim+eng+jpn", variant;
    int tess_psm = 3;
    bool quiet = false;
    OcrOptions opt;
    std::vector<std::string> images;

    for (int i = 1; i < argc; i++)
    {
        std::string a = argv[i];
        auto next = [&](const char* what) -> std::string {
            if (i + 1 >= argc)
            {
                fprintf(stderr, "missing value for %s\n", what);
                exit(2);
            }
            return argv[++i];
        };
        if (a == "--engine") engine_name = next("--engine");
        else if (a == "--assets") assets = next("--assets");
        else if (a == "--out") out_path = next("--out");
        else if (a == "--tessdata") tessdata = next("--tessdata");
        else if (a == "--tess-langs") tess_langs = next("--tess-langs");
        else if (a == "--tess-psm") tess_psm = atoi(next("--tess-psm").c_str());
        else if (a == "--threads") opt.threads = atoi(next("--threads").c_str());
        else if (a == "--det-limit") opt.det_limit = atoi(next("--det-limit").c_str());
        else if (a == "--rec-max-width") opt.rec_max_width = atoi(next("--rec-max-width").c_str());
        else if (a == "--unclip-ratio") opt.unclip_ratio = (float)atof(next("--unclip-ratio").c_str());
        else if (a == "--box-thresh") opt.box_thresh = (float)atof(next("--box-thresh").c_str());
        else if (a == "--det-thresh") opt.det_thresh = (float)atof(next("--det-thresh").c_str());
        else if (a == "--variant") variant = next("--variant");
        else if (a == "--quiet") quiet = true;
        else if (a == "-h" || a == "--help") { usage(argv[0]); return 0; }
        else if (!a.empty() && a[0] == '-') { fprintf(stderr, "unknown option %s\n", a.c_str()); usage(argv[0]); return 2; }
        else images.push_back(a);
    }

    if (engine_name.empty() || assets.empty() || out_path.empty() || images.empty())
    {
        usage(argv[0]);
        return 2;
    }

    if (tessdata.empty())
        tessdata = assets + "/tessdata_fast";

    Engine* eng = nullptr;
    if (engine_name == "ncnn")
        eng = new NcnnPpOcrv5(opt);
#ifdef WP17R2_WITH_TESSERACT
    else if (engine_name == "tesseract")
        eng = new TessOcr(tess_langs, tess_psm, tessdata);
#endif
    else
    {
        fprintf(stderr, "engine '%s' not available in this build\n", engine_name.c_str());
        return 2;
    }

    std::string err;
    double t_load0 = now_ms();
    if (!eng->load(assets, variant, err))
    {
        fprintf(stderr, "load failed: %s\n", err.c_str());
        return 3;
    }
    double load_ms = now_ms() - t_load0;

    std::vector<ImageResult> results;
    double batch0 = now_ms();
    for (size_t i = 0; i < images.size(); i++)
    {
        ImageResult r;
        r.path = images[i];
        double t_all = now_ms();
        Bitmap bm;
        double t0 = now_ms();
        if (!load_png_bgr(images[i], bm))
        {
            r.error = "decode failed";
            r.total_ms = now_ms() - t_all;
            results.push_back(r);
            fprintf(stderr, "[wp17r2] %s ERROR decode\n", images[i].c_str());
            continue;
        }
        r.decode_ms = now_ms() - t0;
        r.width = bm.w;
        r.height = bm.h;
        r.det_channel = 3;
        std::string run_err;
        if (!eng->run(bm, r, run_err))
            r.error = run_err;
        r.total_ms = now_ms() - t_all;
        if (!quiet)
        {
            fprintf(stderr, "[wp17r2] %-34s %5dx%-5d lines=%-4zu det=%7.1f rec=%7.1f total=%8.1f ms %s\n",
                    images[i].c_str(), r.width, r.height, r.lines.size(), r.det_ms, r.rec_ms, r.total_ms,
                    r.error.empty() ? "" : r.error.c_str());
        }
        results.push_back(r);
    }
    double batch_ms = now_ms() - batch0;

    std::string json;
    json += "{\n";
    json += "  \"schema\": \"wp17r2-ocr/1\",\n";
    json += "  \"engine\": \"" + json_escape(eng->name()) + "\",\n";
    json += "  \"engine_version\": \"" + json_escape(eng->version()) + "\",\n";
    json += "  \"variant\": \"" + json_escape(variant) + "\",\n";
    json += "  \"model_load_ms\": " + std::to_string(load_ms) + ",\n";
    json += "  \"batch_total_ms\": " + std::to_string(batch_ms) + ",\n";
    json += "  \"peak_rss_kb\": " + std::to_string(peak_rss_kb()) + ",\n";
    json += "  \"config\": {";
    {
        std::map<std::string, std::string> cfg = eng->config();
        bool first = true;
        for (std::map<std::string, std::string>::const_iterator it = cfg.begin(); it != cfg.end(); ++it)
        {
            json += first ? "\n" : ",\n";
            json += "    \"" + json_escape(it->first) + "\": \"" + json_escape(it->second) + "\"";
            first = false;
        }
        json += "\n";
    }
    json += "  },\n";
    json += "  \"images\": [\n";
    for (size_t i = 0; i < results.size(); i++)
    {
        const ImageResult& r = results[i];
        char buf[256];
        json += "    {\n";
        json += "      \"path\": \"" + json_escape(r.path) + "\",\n";
        snprintf(buf, sizeof(buf), "      \"width\": %d, \"height\": %d,\n", r.width, r.height);
        json += buf;
        snprintf(buf, sizeof(buf), "      \"decode_ms\": %.3f, \"preprocess_ms\": %.3f, \"det_ms\": %.3f, \"rec_ms\": %.3f, \"total_ms\": %.3f,\n",
                 r.decode_ms, r.preprocess_ms, r.det_ms, r.rec_ms, r.total_ms);
        json += buf;
        json += "      \"error\": \"" + json_escape(r.error) + "\",\n";
        json += "      \"lines\": [\n";
        for (size_t j = 0; j < r.lines.size(); j++)
        {
            const TextLine& ln = r.lines[j];
            snprintf(buf, sizeof(buf),
                     "        {\"text\": \"%s\", \"box\": [%.2f, %.2f, %.2f, %.2f], \"score\": %.4f}%s\n",
                     json_escape(ln.text).c_str(), ln.x, ln.y, ln.w, ln.h, ln.score,
                     (j + 1 == r.lines.size()) ? "" : ",");
            json += buf;
        }
        json += "      ]\n";
        json += std::string("    }") + (i + 1 == results.size() ? "\n" : ",\n");
    }
    json += "  ]\n}\n";

    FILE* fp = fopen(out_path.c_str(), "wb");
    if (!fp)
    {
        fprintf(stderr, "cannot write %s\n", out_path.c_str());
        return 4;
    }
    fwrite(json.data(), 1, json.size(), fp);
    fclose(fp);

    if (!quiet)
        fprintf(stderr, "[wp17r2] engine=%s load=%.1f ms batch=%.1f ms peak_rss=%llu kB -> %s\n",
                eng->name().c_str(), load_ms, batch_ms, peak_rss_kb(), out_path.c_str());

    delete eng;
    return 0;
}
