#include "parseOptUtils.h"
#include "decoder.h"
#include "encoder.h"

#include <fstream>
#include <sstream>
#include <iomanip>   // setw / setfill
#include <iostream>

/* -------- 逐帧读取 ROI 文件 -------- */
static bool loadFrameRois(const std::string& path,
                          std::vector<Regions>& rois,
                          float qp_default = 10.0f) {
    std::ifstream fin(path);
    if (!fin.is_open()) return false;      // 文件不存在
    std::string line;
    std::cerr << "Reading ROI file: " << path << "  result=" << rois.size() << "\n";
    while (std::getline(fin, line)) {
        int x1, y1, x2, y2;  char comma;   // 逗号占位
        float qp;
        std::istringstream ss(line);
        if (!(ss >> x1 >> comma >> y1 >> comma >> x2 >> comma >> y2) ||
            ss.peek() != ':' || !(ss.ignore() >> qp))
            continue;                      // 解析失败跳过
        rois.emplace_back(x1/16, y1/16, x2/16, y2/16, qp);
    }
    return !rois.empty();
}
/* ---------------------------------- */

int main(int argc, char **argv) {

    Arguments arguments;
    arguments.parseArguments(argc, argv);

    H264Decoder decoder(arguments.inputPath);
    X264Encoder encoder(arguments.outputPath,
                        decoder.width, decoder.height, arguments.fps);

    int frameCount = 0;

    while (!av_read_frame(decoder.formatContext, decoder.packet)) {

        if (decoder.packet->stream_index != decoder.stream->index) continue;
        if (avcodec_send_packet(decoder.videoCodecContext, decoder.packet) != 0) break;
        av_packet_unref(decoder.packet);

        if (avcodec_receive_frame(decoder.videoCodecContext, decoder.frame) == 0) {

            /* === 每帧读取对应 ROI 文件并设置宏块 QP ================ */
            std::vector<Regions> frameRois;
            std::ostringstream roiFile;
            roiFile << arguments.roi_folder << "/frame_"
                    << std::setw(4) << std::setfill('0') << frameCount
                    << "_multi.txt";                 // 若用 merge.txt 改这里
            loadFrameRois(roiFile.str(), frameRois);
            if (!frameRois.empty())
                encoder.setBlockQp(frameRois, arguments.base_qp);
            //encoder.setBlockQp(frameRois, arguments.base_qp);
            /* ======================================================== */

            ++frameCount;
            if (!encoder.encode(decoder.frame->data, decoder.frame->linesize)) {
                av_log(nullptr, AV_LOG_WARNING, "Encode failed at frame %d\n", frameCount);
            }
            av_frame_unref(decoder.frame);
        }
    }

    /* flush decoder / encoder 与原逻辑相同 */
    if (frameCount < decoder.stream->nb_frames) {
        avcodec_send_packet(decoder.videoCodecContext, nullptr);
        while (avcodec_receive_frame(decoder.videoCodecContext, decoder.frame) != AVERROR_EOF) {
            std::vector<Regions> dummy;
            encoder.setBlockQp(dummy, arguments.base_qp);   // 无 ROI
            encoder.encode(decoder.frame->data, decoder.frame->linesize);
            av_frame_unref(decoder.frame);
        }
    }
    encoder.flush();
    return 0;
}
