from typing import *
import os
import time
import sherpa_onnx
import logging
import numpy as np
import asyncio
import time
import soundfile
from scipy.signal import resample
import io
import re

logger = logging.getLogger(__file__)

splitter = re.compile(r'[,，。.!?！？;；、\n]')
_tts_engines = {}

# Kokoro voice name to speaker ID mapping based on sherpa-onnx documentation
# For kokoro-multi-lang-v1_0 model (53 speakers, IDs 0-52)
KOKORO_VOICE_MAP = {
    # Based on search results, these are known mappings:
    'af': 0,
    'af_bella': 1, 
    'af_nicole': 2,
    'af_sarah': 3,
    'af_sky': 4,
    'am_adam': 5,
    'am_michael': 6,
    'bf_emma': 7,
    'bf_isabella': 8,
    'bm_george': 9,
    'bm_lewis': 10,
    # Additional voices - using sequential IDs
    'af_alloy': 11,
    'af_aoede': 12,
    'af_fdr': 13,
    'af_heart': 14,
    'af_jessica': 15,
    'af_kendra': 16,
    'af_nova': 17,
    'am_benjamin': 18,
    'am_bruce': 19,
    'am_onyx': 20,
    'am_patrick': 21,
    'bf_amelia': 22,
    'bf_angie': 23,
    'bf_sophie': 24,
    'bm_alfred': 25,
    'bm_daniel': 26,
    'bm_oscar': 27,
    # Other language voices
    'af_jp_azusa': 28,
    'af_jp_mei': 29,
    'af_jp_momoka': 30,
    'af_jp_nanami': 31,
    'af_jp_shiori': 32,
    'am_jp_hiro': 33,
    'am_jp_kiyoshi': 34,
    'am_jp_shou': 35,
    'am_jp_takeshi': 36,
    'af_fr_lea': 37,
    'af_fr_elise': 38,
    'af_fr_camille': 39,
    'am_fr_henri': 40,
    'am_fr_louis': 41,
    'af_pt_madalena': 42,
    'af_pt_francisca': 43,
    'am_pt_miguel': 44,
    'am_pt_afonso': 45,
    'af_es_ana': 46,
    'af_es_elena': 47,
    'af_es_christina': 48,
    'am_es_mateo': 49,
    'am_es_diego': 50,
    'af_cn_linglong': 51,
    'af_cn_xiaowen': 52
}

tts_configs = {
    'vits-zh-hf-theresa': {
        'model': 'theresa.onnx',
        'lexicon': 'lexicon.txt',
        'dict_dir': 'dict',
        'tokens': 'tokens.txt',
        'sample_rate': 22050,
        'rule_fsts': ['phone.fst', 'date.fst', 'number.fst', 'new_heteronym.fst'],
    },
    'vits-melo-tts-zh_en': {
        'model': 'model.onnx',
        'lexicon': 'lexicon.txt',
        'dict_dir': 'dict',
        'tokens': 'tokens.txt',
        'sample_rate': 44100,
        'rule_fsts': ['phone.fst', 'date.fst', 'number.fst', 'new_heteronym.fst'],
    },
    'kokoro-multi-lang-v1_0': {
        'model': 'model.onnx',
        #'lexicon': ['lexicon-zh.txt','lexicon-us-en.txt','lexicon-gb-en.txt'],
        'lexicon': 'lexicon-zh.txt',
        'dict_dir': 'dict',
        'tokens': 'tokens.txt',
        'sample_rate': 24000,
        'rule_fsts': ['date-zh.fst', 'number-zh.fst'],
    },
}


def load_tts_model(name: str, model_root: str, provider: str, num_threads: int = 1, max_num_sentences: int = 20) -> sherpa_onnx.OfflineTtsConfig:
    cfg = tts_configs[name]
    fsts = []
    model_dir = os.path.join(model_root, name)
    for f in cfg.get('rule_fsts', ''):
        fsts.append(os.path.join(model_dir, f))
    tts_rule_fsts = ','.join(fsts) if fsts else ''

    if 'kokoro' in name:
        kokoro_model_config = sherpa_onnx.OfflineTtsKokoroModelConfig(
            model=os.path.join(model_dir, cfg['model']),
            voices=os.path.join(model_dir, 'voices.bin'),
            lexicon=os.path.join(model_dir, cfg['lexicon']),
            data_dir=os.path.join(model_dir, 'espeak-ng-data'),
            dict_dir=os.path.join(model_dir, cfg['dict_dir']),
            tokens=os.path.join(model_dir, cfg['tokens']),
        )
        model_config = sherpa_onnx.OfflineTtsModelConfig(
            kokoro=kokoro_model_config,
            provider=provider,
            debug=0,
            num_threads=num_threads,
        )
    elif 'vits' in name:
        vits_model_config = sherpa_onnx.OfflineTtsVitsModelConfig(
            model=os.path.join(model_dir, cfg['model']),
            lexicon=os.path.join(model_dir, cfg['lexicon']),
            dict_dir=os.path.join(model_dir, cfg['dict_dir']),
            tokens=os.path.join(model_dir, cfg['tokens']),
        )
        model_config = sherpa_onnx.OfflineTtsModelConfig(
            vits=vits_model_config,
            provider=provider,
            debug=0,
            num_threads=num_threads,
        )
    
    tts_config = sherpa_onnx.OfflineTtsConfig(
        model=model_config,
        rule_fsts=tts_rule_fsts,
        max_num_sentences=max_num_sentences)

    if not tts_config.validate():
        logger.error(f"TTS config validation failed for model: {name}")
        logger.error(f"Model dir: {model_dir}")
        logger.error(f"Model file: {os.path.join(model_dir, cfg['model'])}")
        logger.error(f"Model exists: {os.path.exists(os.path.join(model_dir, cfg['model']))}")
        logger.error(f"Lexicon: {os.path.join(model_dir, cfg['lexicon'])}")
        logger.error(f"Lexicon exists: {os.path.exists(os.path.join(model_dir, cfg['lexicon']))}")
        logger.error(f"Tokens: {os.path.join(model_dir, cfg['tokens'])}")
        logger.error(f"Tokens exists: {os.path.exists(os.path.join(model_dir, cfg['tokens']))}")
        logger.error(f"Voices: {os.path.join(model_dir, 'voices.bin')}")
        logger.error(f"Voices exists: {os.path.exists(os.path.join(model_dir, 'voices.bin'))}")
        logger.error(f"Rule FSTs: {tts_rule_fsts}")
        raise ValueError("tts: invalid config")

    return tts_config


def get_tts_engine(args) -> Tuple[sherpa_onnx.OfflineTts, int]:
    sample_rate = tts_configs[args.tts_model]['sample_rate']
    cache_engine = _tts_engines.get(args.tts_model)
    if cache_engine:
        return cache_engine, sample_rate
    st = time.time()
    tts_config = load_tts_model(
        args.tts_model, args.models_root, args.tts_provider, args.threads)

    cache_engine = sherpa_onnx.OfflineTts(tts_config)
    elapsed = time.time() - st
    logger.info(f"tts: loaded {args.tts_model} in {elapsed:.2f}s")
    _tts_engines[args.tts_model] = cache_engine

    return cache_engine, sample_rate


class TTSResult:
    def __init__(self, pcm_bytes: bytes, finished: bool):
        self.pcm_bytes = pcm_bytes
        self.finished = finished
        self.progress: float = 0.0
        self.elapsed: float = 0.0
        self.audio_duration: float = 0.0
        self.audio_size: int = 0

    def to_dict(self):
        return {
            "progress": self.progress,
            "elapsed": f'{int(self.elapsed * 1000)}ms',
            "duration": f'{self.audio_duration:.2f}s',
            "size": self.audio_size
        }


class TTSStream:
    def __init__(self, engine, sid: Union[int, str], speed: float = 1.0, sample_rate: int = 16000, original_sample_rate: int = 16000, model_name: str = None):
        self.engine = engine
        # Convert sid to integer
        try:
            self.sid = sid if isinstance(sid, int) else int(sid)
        except (ValueError, TypeError):
            logger.warning(f"Invalid speaker ID '{sid}', using default 0")
            self.sid = 0
        self.speed = speed
        self.outbuf: asyncio.Queue[TTSResult | None] = asyncio.Queue()
        self.is_closed = False
        self.target_sample_rate = sample_rate
        self.original_sample_rate = original_sample_rate

    def on_process(self, chunk: np.ndarray, progress: float):
        if self.is_closed:
            return 0

        # resample to target sample rate
        if self.target_sample_rate != self.original_sample_rate:
            num_samples = int(
                len(chunk) * self.target_sample_rate / self.original_sample_rate)
            resampled_chunk = resample(chunk, num_samples)
            chunk = resampled_chunk.astype(np.float32)

        scaled_chunk = chunk * 32768.0
        clipped_chunk = np.clip(scaled_chunk, -32768, 32767)
        int16_chunk = clipped_chunk.astype(np.int16)
        samples = int16_chunk.tobytes()
        self.outbuf.put_nowait(TTSResult(samples, False))
        return self.is_closed and 0 or 1

    async def write(self, text: str, split: bool, pause: float = 0.2):
        start = time.time()
        if split:
            texts = re.split(splitter, text)
        else:
            texts = [text]

        audio_duration = 0.0
        audio_size = 0

        for idx, text in enumerate(texts):
            text = text.strip()
            if not text:
                continue
            sub_start = time.time()

            # Ensure sid is an integer for generate() call
            sid_int = self.sid if isinstance(self.sid, int) else 0
            logger.debug(f"TTS generate: text='{text}', sid={sid_int} (from {self.sid}), speed={self.speed}")
            
            audio = await asyncio.to_thread(self.engine.generate,
                                            text, sid_int, self.speed,
                                            self.on_process)

            if not audio or not audio.sample_rate or not audio.samples:
                logger.error(f"tts: failed to generate audio for "
                             f"'{text}' (audio={audio})")
                continue

            if split and idx < len(texts) - 1:  # add a pause between sentences
                noise = np.zeros(int(audio.sample_rate * pause))
                self.on_process(noise, 1.0)
                audio.samples = np.concatenate([audio.samples, noise])

            audio_duration += len(audio.samples) / audio.sample_rate
            audio_size += len(audio.samples)
            elapsed_seconds = time.time() - sub_start
            logger.info(f"tts: generated audio for '{text}', "
                        f"audio duration: {audio_duration:.2f}s, "
                        f"elapsed: {elapsed_seconds:.2f}s")

        elapsed_seconds = time.time() - start
        logger.info(f"tts: generated audio in {elapsed_seconds:.2f}s, "
                    f"audio duration: {audio_duration:.2f}s")

        r = TTSResult(None, True)
        r.elapsed = elapsed_seconds
        r.audio_duration = audio_duration
        r.progress = 1.0
        r.finished = True
        await self.outbuf.put(r)

    async def close(self):
        self.is_closed = True
        self.outbuf.put_nowait(None)
        logger.info("tts: stream closed")

    async def read(self) -> TTSResult:
        return await self.outbuf.get()

    async def generate(self,  text: str) -> io.BytesIO:
        start = time.time()
        audio = await asyncio.to_thread(self.engine.generate,
                                        text, self.sid, self.speed)
        elapsed_seconds = time.time() - start
        audio_duration = len(audio.samples) / audio.sample_rate

        logger.info(f"tts: generated audio in {elapsed_seconds:.2f}s, "
                    f"audio duration: {audio_duration:.2f}s, "
                    f"sample rate: {audio.sample_rate}")

        if self.target_sample_rate != audio.sample_rate:
            audio.samples = resample(audio.samples,
                                     int(len(audio.samples) * self.target_sample_rate / audio.sample_rate))
            audio.sample_rate = self.target_sample_rate

        output = io.BytesIO()
        soundfile.write(output,
                        audio.samples,
                        samplerate=audio.sample_rate,
                        subtype="PCM_16",
                        format="WAV")
        output.seek(0)
        return output


async def start_tts_stream(sid: Union[int, str], sample_rate: int, speed: float, args) -> TTSStream:
    engine, original_sample_rate = get_tts_engine(args)
    return TTSStream(engine, sid, speed, sample_rate, original_sample_rate, model_name=args.tts_model)
