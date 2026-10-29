using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Video;

namespace Oxipital
{
    [DefaultExecutionOrder(-100)]
    [DisallowMultipleComponent]
    public sealed class OpticalFlowVideoInput : MonoBehaviour
    {
        [Header("Webcam")]
        [Tooltip("Empty selects the first webcam. Use Restart Webcam after changing these settings.")]
        public string deviceName = "";
        [Min(16)] public int cameraWidth = 640;
        [Min(16)] public int cameraHeight = 480;
        [Range(1, 60)] public int cameraFrameRate = 30;

        [Header("Video")]
        public VideoClip clip;
        [Tooltip("Local video path, URL, or recording.json. Takes priority over Clip. Press Load / Play to apply.")]
        public string videoPath = "";
        public bool loop = true;
        [Range(.1f, 4)] public float playbackSpeed = 1;
        [Range(0, 1), Tooltip("0 = webcam, 1 = video.")]
        public float videoBlend = .5f;
        [Range(64, 1280), Tooltip("Optical flow working width. Height follows the source aspect ratio. Blend uses the webcam aspect ratio; the video is fitted with black borders.")]
        public int processingWidth = 320;

        [Header("Recording (JPEG sequence, no audio)")]
        [Range(1, 60), Tooltip("JPEG encoding and disk writes run on the main thread. Reduce camera resolution or this rate if recording affects rendering. Frames retain their actual capture timestamps.")]
        public int recordingFrameRate = 15;
        [Range(1, 100)] public int jpegQuality = 85;
        [Min(1)] public float maxRecordingSeconds = 120;
        [Tooltip("After Stop, load the saved recording and switch Optical Flow Source to Video. Recordings are saved under Application.persistentDataPath/WebcamRecordings.")]
        public bool playRecordingOnStop = true;
        [Tooltip("Displays source selection, playback and Record buttons in the built application.")]
        public bool showControls;

        [OSCQuery.DoNotExpose, SerializeField] string lastRecordingPath;
        WebCamTexture cameraTexture;
        VideoPlayer player;
        WebcamRecording recording, sequence;
        Coroutine cameraRequest;
        bool cameraAttempted, autoLoadAttempted, sequencePlaying, recordingRequested;
        bool cameraHasFrame, videoHasFrame;
        double sequenceTime, recordingStarted;
        int cameraSignature;

        public int Revision { get; private set; }
        public bool IsRecording => recording != null && recording.IsRecording;
        public bool IsRecordingPending => recordingRequested;
        public bool WebcamReady => cameraHasFrame && cameraTexture != null && cameraTexture.isPlaying && cameraTexture.width > 16 && cameraTexture.height > 16;
        public bool IsPlaying => sequence != null ? sequencePlaying : player != null && player.isPlaying;
        public string LastRecordingPath => lastRecordingPath;
        public string Status { get; private set; } = "Ready";
        public Texture WebcamTexture => WebcamReady ? cameraTexture : null;
        public Texture VideoTexture => sequence != null ? sequence.Texture : videoHasFrame && player != null && player.isPrepared ? player.texture : null;

        void OnEnable()
        {
            if (string.IsNullOrEmpty(lastRecordingPath))
                lastRecordingPath = PlayerPrefs.GetString("Oxipital.Webcam.LastRecording", "");
        }

        internal void PrepareInput(OpticalFlowSource.FlowSourceMode mode)
        {
            if (!isActiveAndEnabled) return;
            bool cameraWanted = mode == OpticalFlowSource.FlowSourceMode.Webcam || mode == OpticalFlowSource.FlowSourceMode.Blend;
            if (cameraWanted && !cameraAttempted) StartWebcam();
            bool needsVideo = mode == OpticalFlowSource.FlowSourceMode.Video || mode == OpticalFlowSource.FlowSourceMode.Blend;
            if (needsVideo && !autoLoadAttempted && (clip != null || !string.IsNullOrWhiteSpace(videoPath))) LoadVideo();
        }

        public void StartWebcam()
        {
            if (!Application.isPlaying || !isActiveAndEnabled || cameraRequest != null || cameraTexture != null) return;
            cameraAttempted = true;
            cameraRequest = StartCoroutine(OpenWebcam());
        }

        IEnumerator OpenWebcam()
        {
            yield return Application.RequestUserAuthorization(UserAuthorization.WebCam);
            cameraRequest = null;
            if (!Application.HasUserAuthorization(UserAuthorization.WebCam))
            {
                recordingRequested = false;
                Status = "Webcam access denied";
                yield break;
            }
            var devices = WebCamTexture.devices;
            string selected = null;
            foreach (var device in devices)
                if (string.IsNullOrEmpty(deviceName) || device.name == deviceName) { selected = device.name; break; }
            if (selected == null) { recordingRequested = false; Status = "Webcam not found"; yield break; }
            cameraTexture = new WebCamTexture(selected, Mathf.Max(16, cameraWidth), Mathf.Max(16, cameraHeight), Mathf.Clamp(cameraFrameRate, 1, 60));
            cameraTexture.Play();
            Status = "Starting webcam: " + selected;
            Revision++;
        }

        public void RestartWebcam()
        {
            if (IsRecording) StopRecording();
            StopWebcam();
            StartWebcam();
        }

        public void StopWebcam()
        {
            recordingRequested = false;
            if (IsRecording) StopRecording(false);
            if (cameraRequest != null) StopCoroutine(cameraRequest);
            cameraRequest = null;
            if (cameraTexture != null) { cameraTexture.Stop(); Destroy(cameraTexture); }
            cameraTexture = null;
            cameraHasFrame = false;
            cameraAttempted = false;
            cameraSignature = 0;
            Revision++;
        }

        public void LoadVideo()
        {
            if (!Application.isPlaying || !isActiveAndEnabled) return;
            autoLoadAttempted = true;
            CloseVideo();
            Revision++;
            try
            {
                if (videoPath.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                {
                    sequence = new WebcamRecording();
                    sequence.Load(videoPath);
                    sequencePlaying = true;
                    Status = "Playing webcam recording";
                    return;
                }
                if (clip == null && string.IsNullOrWhiteSpace(videoPath)) { Status = "Select a video first"; return; }
                player = gameObject.AddComponent<VideoPlayer>();
                player.playOnAwake = false;
                player.renderMode = VideoRenderMode.APIOnly;
                player.audioOutputMode = VideoAudioOutputMode.None;
                player.waitForFirstFrame = true;
                player.sendFrameReadyEvents = true;
                player.isLooping = loop;
                player.playbackSpeed = Mathf.Clamp(playbackSpeed, .1f, 4);
                player.errorReceived += OnVideoError;
                player.prepareCompleted += OnVideoPrepared;
                player.loopPointReached += OnVideoLoop;
                player.seekCompleted += OnVideoSeek;
                player.frameReady += OnVideoFrame;
                if (!string.IsNullOrWhiteSpace(videoPath))
                {
                    player.source = VideoSource.Url;
                    player.url = Uri.TryCreate(videoPath, UriKind.Absolute, out var uri)
                        ? uri.AbsoluteUri : new Uri(Path.GetFullPath(videoPath)).AbsoluteUri;
                }
                else { player.source = VideoSource.VideoClip; player.clip = clip; }
                player.Play();
                Status = "Loading video";
            }
            catch (Exception e) when (IsMediaError(e)) { CloseVideo(); Report(e.Message); }
        }

        public void PlayPause()
        {
            if (sequence != null)
            {
                if (!loop && sequenceTime >= sequence.Duration) { sequenceTime = 0; Revision++; }
                sequencePlaying = !sequencePlaying;
            }
            else if (player != null)
            {
                if (player.isPlaying) player.Pause(); else player.Play();
            }
            else LoadVideo();
        }

        public void Rewind()
        {
            sequenceTime = 0;
            if (player != null && player.isPrepared && player.canSetTime) player.time = 0;
            Revision++;
        }

        public void ToggleRecording()
        {
            if (IsRecording) StopRecording();
            else if (recordingRequested) { recordingRequested = false; Status = "Recording cancelled"; }
            else StartRecording();
        }

        public void StartRecording()
        {
            if (!Application.isPlaying || !isActiveAndEnabled || IsRecording) return;
            if (!WebcamReady)
            {
                recordingRequested = true;
                StartWebcam();
                Status = "Waiting for webcam to start recording";
                return;
            }
            recordingRequested = false;
            try
            {
                recording = new WebcamRecording();
                recording.Begin(cameraTexture);
                recordingStarted = Time.realtimeSinceStartupAsDouble;
                recording.Capture(cameraTexture, recordingFrameRate, jpegQuality);
                Status = "Recording webcam";
            }
            catch (Exception e) when (IsMediaError(e)) { StopRecording(false); Report(e.Message); }
        }

        public void StopRecording() => StopRecording(playRecordingOnStop);

        void StopRecording(bool play)
        {
            recordingRequested = false;
            if (recording == null) return;
            string path = null;
            try { path = recording.Finish(); }
            catch (Exception e) when (IsMediaError(e)) { Report(e.Message); }
            finally { recording.Dispose(); recording = null; }
            if (path == null) return;
            lastRecordingPath = path;
            PlayerPrefs.SetString("Oxipital.Webcam.LastRecording", path);
            PlayerPrefs.Save();
            Status = "Saved: " + path;
            if (play) UseLastRecording();
        }

        public void UseLastRecording()
        {
            if (string.IsNullOrEmpty(lastRecordingPath)) return;
            videoPath = lastRecordingPath;
            LoadVideo();
            var source = GetComponent<OpticalFlowSource>();
            if (source != null) { source.useTestSource = false; source.mode = OpticalFlowSource.FlowSourceMode.Video; }
        }

        void Update()
        {
            if (cameraTexture != null && cameraTexture.didUpdateThisFrame && cameraTexture.width > 16 && cameraTexture.height > 16)
                cameraHasFrame = true;
            if (WebcamReady)
            {
                int signature = cameraTexture.width ^ (cameraTexture.height << 12) ^ (cameraTexture.videoRotationAngle << 24) ^ (cameraTexture.videoVerticallyMirrored ? 1 : 0);
                if (signature != cameraSignature) { cameraSignature = signature; Revision++; }
            }
            if (recordingRequested && WebcamReady) StartRecording();
            if (IsRecording)
            {
                try
                {
                    if (!WebcamReady) throw new IOException("Webcam disconnected during recording.");
                    recording.Capture(cameraTexture, recordingFrameRate, jpegQuality);
                    if (Time.realtimeSinceStartupAsDouble - recordingStarted >= Mathf.Max(1, maxRecordingSeconds)) StopRecording();
                }
                catch (Exception e) when (IsMediaError(e)) { StopRecording(false); Report(e.Message); }
            }
            if (player != null) { player.isLooping = loop; player.playbackSpeed = Mathf.Clamp(playbackSpeed, .1f, 4); }
            if (sequence == null) return;
            try
            {
                if (sequencePlaying)
                {
                    sequenceTime += Time.unscaledDeltaTime * Mathf.Clamp(playbackSpeed, .1f, 4);
                    if (sequenceTime >= sequence.Duration)
                    {
                        if (loop) { sequenceTime %= sequence.Duration; Revision++; }
                        else { sequenceTime = sequence.Duration; sequencePlaying = false; }
                    }
                }
                sequence.Sample(sequenceTime);
            }
            catch (Exception e) when (IsMediaError(e)) { CloseVideo(); Revision++; Report(e.Message); }
        }

        internal Vector2Int WorkingSize(OpticalFlowSource.FlowSourceMode mode)
        {
            bool webcam = mode != OpticalFlowSource.FlowSourceMode.Video;
            Texture texture = webcam ? WebcamTexture : VideoTexture;
            int rotation = webcam ? (WebcamReady ? cameraTexture.videoRotationAngle : 0) : sequence?.Rotation ?? 0;
            float aspect = texture != null ? (float)texture.width / texture.height : (float)Mathf.Max(16, cameraWidth) / Mathf.Max(16, cameraHeight);
            if (rotation % 180 != 0) aspect = 1 / aspect;
            int width = Mathf.Clamp(processingWidth, 64, 1280);
            return new Vector2Int(width, Mathf.Clamp(Mathf.RoundToInt(width / aspect), 16, 1280));
        }

        internal void Render(ComputeShader shader, RenderTexture target, OpticalFlowSource.FlowSourceMode mode)
        {
            Texture webcam = WebcamTexture;
            Texture video = VideoTexture;
            int kernel = shader.FindKernel("VideoInput");
            shader.SetInts("_Size", target.width, target.height);
            shader.SetTexture(kernel, "_Webcam", webcam != null ? webcam : Texture2D.blackTexture);
            shader.SetTexture(kernel, "_Video", video != null ? video : Texture2D.blackTexture);
            shader.SetTexture(kernel, "_VideoOut", target);
            shader.SetVector("_WebcamInfo", TextureInfo(webcam, WebcamReady ? cameraTexture.videoRotationAngle : 0, WebcamReady && cameraTexture.videoVerticallyMirrored));
            shader.SetVector("_VideoInfo", TextureInfo(video, sequence?.Rotation ?? 0, sequence != null && sequence.FlipY));
            float blend = mode == OpticalFlowSource.FlowSourceMode.Webcam ? 0 : mode == OpticalFlowSource.FlowSourceMode.Video ? 1 : Mathf.Clamp01(videoBlend);
            shader.SetFloat("_VideoBlend", blend);
            OpticalFlowUtil.Dispatch(shader, kernel, target.width, target.height);
        }

        static Vector4 TextureInfo(Texture texture, int rotation, bool flip)
        {
            float aspect = texture != null ? (float)texture.width / texture.height : 1;
            if (rotation % 180 != 0) aspect = 1 / aspect;
            return new Vector4(aspect, rotation / 90, flip ? 1 : 0, texture != null ? 1 : 0);
        }

        static bool IsMediaError(Exception e) => e is IOException || e is UnauthorizedAccessException || e is ArgumentException || e is UnityException;
        void Report(string message) { Status = message; Debug.LogWarning("OpticalFlowVideoInput: " + message, this); }
        void OnVideoError(VideoPlayer sender, string message) { CloseVideo(); Revision++; Report(message); }
        void OnVideoPrepared(VideoPlayer sender) { Revision++; Status = "Playing video"; }
        void OnVideoFrame(VideoPlayer sender, long index)
        {
            videoHasFrame = true;
            sender.sendFrameReadyEvents = false;
            Revision++;
        }
        void OnVideoLoop(VideoPlayer sender) { if (sender.isLooping) Revision++; }
        void OnVideoSeek(VideoPlayer sender) { Revision++; }

        void CloseVideo()
        {
            if (player != null)
            {
                player.errorReceived -= OnVideoError;
                player.prepareCompleted -= OnVideoPrepared;
                player.loopPointReached -= OnVideoLoop;
                player.seekCompleted -= OnVideoSeek;
                player.frameReady -= OnVideoFrame;
                player.Stop();
                Destroy(player);
            }
            player = null;
            videoHasFrame = false;
            sequence?.Dispose();
            sequence = null;
            sequenceTime = 0;
            sequencePlaying = false;
        }

        void OnDisable()
        {
            StopRecording(false);
            StopWebcam();
            CloseVideo();
            autoLoadAttempted = false;
        }

        void OnGUI()
        {
            if (!showControls) return;
            GUILayout.BeginArea(new Rect(10, 10, 350, 370), GUI.skin.box);
            var source = GetComponent<OpticalFlowSource>();
            if (source != null)
            {
                string[] modes = { "Webcam", "Video", "Blend" };
                int selected = (int)source.mode - (int)OpticalFlowSource.FlowSourceMode.Webcam;
                int next = GUILayout.Toolbar(selected, modes);
                if (next != selected && next >= 0) { source.mode = (OpticalFlowSource.FlowSourceMode)(next + 2); source.useTestSource = false; }
            }
            GUILayout.Label("Video blend: " + videoBlend.ToString("F2"));
            videoBlend = GUILayout.HorizontalSlider(videoBlend, 0, 1);
            videoPath = GUILayout.TextField(videoPath);
            if (GUILayout.Button("Load / Play")) LoadVideo();
            if (GUILayout.Button(IsPlaying ? "Pause" : "Play")) PlayPause();
            if (GUILayout.Button("Rewind")) Rewind();
            if (GUILayout.Button(IsRecording ? "Stop recording" : IsRecordingPending ? "Cancel recording request" : "Record webcam")) ToggleRecording();
            GUI.enabled = !string.IsNullOrEmpty(lastRecordingPath);
            if (GUILayout.Button("Use last recording")) UseLastRecording();
            GUI.enabled = true;
            GUILayout.Label(Status);
            GUILayout.EndArea();
        }
    }
}
