// Jarvis Voice Client - Web Audio API + WebSocket
// All bugs fixed: 2026-04-05 comprehensive rewrite - Safari wake word fix

class JarvisVoiceClient {
    constructor() {
        this.ws = null;
        this.audioContext = null;
        this.analyser = null;
        this.mediaRecorder = null;
        this.recordedChunks = [];
        this._micStream = null;
        this.isConnected = false;
        this.isRecording = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectTimeout = null;
        this.wsUrl = this.determineWsUrl();
        this.autoTriggered = false;
        this.wakeWordEngine = null;
        this.wakeWordActive = false;
        this.silenceTimer = null;
        this._silenceDetectionInterval = null;
        this._ttsAudioBuffer = null;
        this._wakeWordErrorCount = 0;
        this._wakeWordCooldown = false;
        this._isSpeaking = false;
        this._isAckPlaying = false;
        this._awaitingBackend = false;
        this._ackRawBuffers = null;
        this._ackDecodedBuffers = {};
        this._expectingReply = false;
        this._audioQueue = [];
        this._isPlayingQueue = false;
        this._partialResponseText = '';
        this._phase = 'idle';
        this._wakeWordRestartTimeout = null;
        this.voiceResponseEnabled = localStorage.getItem('jarvis_voice_response') !== 'false';

        this.elements = {
            recordButton: document.getElementById('recordButton'),
            wakeWordButton: document.getElementById('wakeWordButton'),
            wakeWordIcon: document.getElementById('wakeWordIcon'),
            wakeWordText: document.getElementById('wakeWordText'),
            statusDot: document.getElementById('statusDot'),
            statusText: document.getElementById('statusText'),
            transcription: document.getElementById('transcription'),
            response: document.getElementById('response'),
            spinner: document.getElementById('spinner'),
            errorMessage: document.getElementById('errorMessage'),
            ipHint: document.getElementById('ipHint'),
            waveformCanvas: document.getElementById('waveformCanvas'),
            voiceToggleButton: document.getElementById('voiceToggleButton'),
            voiceToggleIcon: document.getElementById('voiceToggleIcon'),
            voiceToggleText: document.getElementById('voiceToggleText'),
        };

        this.init();
    }

    init() {
        this.connect();
        this.setupEventListeners();
        this.animateParticles();
        this.updateIPHint();
        this.preloadAckPhrases();
        this.startWakeWordWatchdog();
        this._updateVoiceToggleUI();
        // Reconectar ao voltar para a aba (Safari suspende WS em background)
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden && !this.isConnected) {
                console.log('[Visibility] Page visible, reconnecting...');
                this.reconnectAttempts = 0;
                this.connect();
            }
        });
    }

    determineWsUrl() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = window.location.hostname || 'localhost';
        const port = window.location.port || '8765';
        const token = localStorage.getItem('jarvis_client_token') || '';
        const query = token ? `?token=${encodeURIComponent(token)}` : '';
        return `${protocol}//${host}:${port}/ws${query}`;
    }

    connect() {
        try {
            if (this.reconnectTimeout) {
                clearTimeout(this.reconnectTimeout);
                this.reconnectTimeout = null;
            }
            if (this.ws && this.ws.readyState !== WebSocket.CLOSED) {
                this.ws.onclose = null;
                this.ws.close();
                this.ws = null;
            }
            this.ws = new WebSocket(this.wsUrl);

            this.ws.onopen = () => {
                console.log('WebSocket connected');
                this.isConnected = true;
                this.reconnectAttempts = 0;
                this.updateStatus('connected');
            };

            this.ws.onmessage = (event) => {
                if (event.data instanceof ArrayBuffer || event.data instanceof Blob) {
                    this.playAudioResponseBinary(event.data);
                    return;
                }
                this.handleMessage(event);
            };

            this.ws.onerror = () => {
                console.error('WebSocket error');
            };

            this.ws.onclose = () => {
                console.log('WebSocket closed');
                this.isConnected = false;
                this.scheduleReconnect();
            };
        } catch (error) {
            console.error('Connection error:', error);
            this.scheduleReconnect();
        }
    }

    scheduleReconnect() {
        if (this.reconnectTimeout) return;
        const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 15000);
        this.reconnectAttempts++;
        console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
        this.updateStatus('reconnecting');
        this.reconnectTimeout = setTimeout(() => {
            this.reconnectTimeout = null;
            this.connect();
        }, delay);
    }

    handleMessage(event) {
        try {
            const data = JSON.parse(event.data);
            switch (data.type) {
                case 'status':
                    this.updateStatus(data.message);
                    break;
                case 'transcription':
                    this.showTranscription(data.text);
                    this._isSpeaking = false;
                    break;
                case 'no_speech':
                    this._awaitingBackend = false;
                    this._setPhase('idle', 'transcrição vazia');
                    this.updateStatus('connected');
                    this._scheduleWakeWordRestart(300, 'sem fala detectada');
                    break;
                case 'partial_response':
                    // Streaming: show text progressively
                    this._partialResponseText += (this._partialResponseText ? ' ' : '') + data.text;
                    this.showResponse(this._partialResponseText);
                    break;
                case 'audio_chunk_end':
                    // Streaming: signal that current sentence audio is complete
                    // Audio is already queued from binary messages
                    break;
                case 'response':
                    // Final response (after streaming or non-streaming)
                    this._awaitingBackend = false;
                    this._partialResponseText = '';
                    this.showResponse(data.text);
                    this._expectingReply = !!data.expectingReply;
                    // Se existe áudio tocando/enfileirado, a decisão pós-resposta acontece no fim do TTS.
                    if (this.voiceResponseEnabled && (this._isSpeaking || this._isPlayingQueue || this._audioQueue.length > 0)) {
                        return;
                    }
                    // Fallback: reativar wake word ou escuta contínua se nenhum áudio binário tocou.
                    setTimeout(() => {
                        if (this.isRecording) return;
                        if (this._expectingReply) {
                            this._startConversationListen();
                        } else {
                            if (!this._isSpeaking && !this._isPlayingQueue) {
                                this._setPhase('idle', 'resposta sem áudio');
                            }
                            this._scheduleWakeWordRestart(500, 'resposta sem áudio');
                        }
                    }, 500);
                    break;
                case 'error':
                    this._awaitingBackend = false;
                    this._isSpeaking = false;
                    this._setPhase('idle', 'erro no backend');
                    this.handleError(data.message);
                    // Reativar wake word após erro para não travar o fluxo
                    this._scheduleWakeWordRestart(500, 'erro no backend');
                    break;
                default:
                    console.log('Unknown message type:', data.type);
            }
        } catch (error) {
            console.error('Message parsing error:', error);
        }
    }

    setupEventListeners() {
        const btn = this.elements.recordButton;
        btn.addEventListener('touchstart', (e) => { e.preventDefault(); this.startRecording(); });
        btn.addEventListener('touchend', (e) => { e.preventDefault(); this.stopRecording(); });
        btn.addEventListener('mousedown', (e) => { e.preventDefault(); this.startRecording(); });
        btn.addEventListener('mouseup', (e) => { e.preventDefault(); this.stopRecording(); });
        btn.addEventListener('mouseleave', (e) => { if (this.isRecording) this.stopRecording(); });
        btn.addEventListener('touchmove', (e) => { e.preventDefault(); }, { passive: false });
        if (this.elements.wakeWordButton) {
            this.elements.wakeWordButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.toggleWakeWord();
            });
        }
        if (this.elements.voiceToggleButton) {
            this.elements.voiceToggleButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.toggleVoiceResponse();
            });
        }
    }

    toggleVoiceResponse() {
        this.voiceResponseEnabled = !this.voiceResponseEnabled;
        localStorage.setItem('jarvis_voice_response', this.voiceResponseEnabled ? 'true' : 'false');
        this._updateVoiceToggleUI();
    }

    _updateVoiceToggleUI() {
        if (!this.elements.voiceToggleButton) return;
        if (this.voiceResponseEnabled) {
            this.elements.voiceToggleIcon.textContent = '🔊';
            this.elements.voiceToggleText.textContent = 'Resposta por voz: ON';
            this.elements.voiceToggleButton.classList.add('active');
        } else {
            this.elements.voiceToggleIcon.textContent = '🔇';
            this.elements.voiceToggleText.textContent = 'Resposta por voz: OFF';
            this.elements.voiceToggleButton.classList.remove('active');
        }
    }

    _setPhase(nextPhase, reason = '') {
        if (this._phase === nextPhase) return;
        const suffix = reason ? ` (${reason})` : '';
        console.log(`[Phase] ${this._phase} -> ${nextPhase}${suffix}`);
        this._phase = nextPhase;
    }

    _clearWakeWordRestart() {
        if (this._wakeWordRestartTimeout) {
            clearTimeout(this._wakeWordRestartTimeout);
            this._wakeWordRestartTimeout = null;
        }
    }

    _canRunWakeWord() {
        return (this._phase === 'idle' || this._phase === 'wake_listening') &&
            this.wakeWordActive &&
            !this.isRecording &&
            !this._awaitingBackend &&
            !this._isSpeaking &&
            !this._isPlayingQueue &&
            !this._isAckPlaying &&
            !this._expectingReply;
    }

    _scheduleWakeWordRestart(delay = 300, reason = '') {
        if (!this._canRunWakeWord() || this.wakeWordEngine) return;
        this._clearWakeWordRestart();
        this._wakeWordRestartTimeout = setTimeout(() => {
            this._wakeWordRestartTimeout = null;
            if (this._canRunWakeWord() && this.wakeWordEngine === null) {
                console.log(`[WakeWord] Reativando listener${reason ? `: ${reason}` : ''}`);
                this.enableWakeWord();
            }
        }, delay);
    }

    toggleWakeWord() {
        if (this.wakeWordActive) this.disableWakeWord();
        else this.enableWakeWord();
    }

    enableWakeWord() {
        this.wakeWordActive = true;
        this._clearWakeWordRestart();
        if (this.elements.wakeWordIcon) this.elements.wakeWordIcon.textContent = '🎧';
        if (this.elements.wakeWordButton) this.elements.wakeWordButton.classList.add('active');
        if (!this._canRunWakeWord()) {
            if (this.elements.wakeWordText) this.elements.wakeWordText.textContent = 'Jarvis armado';
            return;
        }

        // Guard: prevenir criação de engine duplicado
        if (this.wakeWordEngine) {
            console.log('Wake word já ativo, pulando');
            return;
        }

        const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SR) {
            this.handleError('Wake word não suportado. Use Safari.');
            return;
        }

        this.wakeWordEngine = new SR();
        this.wakeWordEngine.continuous = true;
        this.wakeWordEngine.interimResults = true;
        this.wakeWordEngine.lang = 'pt-BR';
        this.wakeWordEngine.maxAlternatives = 3;

        this.wakeWordEngine.onresult = (event) => {
            if (this._wakeWordCooldown) return;
            for (let i = event.resultIndex; i < event.results.length; i++) {
                // Checar todas as alternativas para maior chance de detectar
                let detected = false;
                for (let j = 0; j < event.results[i].length; j++) {
                    if (event.results[i][j].transcript.toLowerCase().includes('jarvis')) {
                        detected = true;
                        break;
                    }
                }
                if (detected) {
                    console.log('Wake word detected!');
                    this._wakeWordCooldown = true;
                    setTimeout(() => { this._wakeWordCooldown = false; }, 3000);

                    const interruptingReply = this._isSpeaking || this._isPlayingQueue || this._awaitingBackend;
                    this.stopTTSPlayback(interruptingReply);
                    if (this.isRecording) this._stopRecordingSilent();

                    if (this._silenceDetectionInterval) {
                        clearInterval(this._silenceDetectionInterval);
                        this._silenceDetectionInterval = null;
                    }

                    this.autoTriggered = true;
                    this.stopWakeWordEngine();
                    this._setPhase('ack_playing', 'wake word detectado');
                    this.elements.wakeWordText.textContent = '✅ "Jarvis" detectado!';

                    // Pré-adquirir mic DURANTE o ack playback (em paralelo)
                    const micPromise = navigator.mediaDevices.getUserMedia({
                        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
                    }).catch(() => null);

                    this._speakAcknowledgment(async () => {
                        const stream = await micPromise;
                        if (stream) {
                            this._startRecordingWithStream(stream);
                        } else {
                            this.startRecording();
                        }
                    });
                    break;
                }
            }
        };

        this.wakeWordEngine.onerror = (ev) => {
            console.log('SpeechRecognition error:', ev.error);
            if (ev.error === 'no-speech' || ev.error === 'aborted') return;
            this._wakeWordErrorCount++;
            const delay = Math.min(500 * this._wakeWordErrorCount, 3000);
            this._setPhase('idle', `erro ${ev.error}`);
            this._scheduleWakeWordRestart(delay, `erro ${ev.error}`);
        };

        this.wakeWordEngine.onend = () => {
            this.wakeWordEngine = null;
            if (this._canRunWakeWord()) {
                this._wakeWordErrorCount = 0;
                this._scheduleWakeWordRestart(300, 'speech recognition terminou');
            }
        };

        try {
            this.wakeWordEngine.start();
            this._wakeWordErrorCount = 0;
            this._setPhase('wake_listening', 'wake word ativo');
            this.elements.wakeWordIcon.textContent = '🎧';
            this.elements.wakeWordText.textContent = 'Ouvindo "Jarvis..."';
            this.elements.wakeWordButton.classList.add('active');
        } catch (e) {
            console.error('Failed to start wake word:', e);
            if (this.elements.wakeWordText) this.elements.wakeWordText.textContent = 'Falha ao ativar Jarvis';
        }
    }

    disableWakeWord() {
        this.wakeWordActive = false;
        this._clearWakeWordRestart();
        this.stopWakeWordEngine();
        this._setPhase('idle', 'wake word desativado');
        if (this.elements.wakeWordIcon) this.elements.wakeWordIcon.textContent = '🎤';
        if (this.elements.wakeWordText) this.elements.wakeWordText.textContent = 'Ativar "Jarvis"';
        if (this.elements.wakeWordButton) this.elements.wakeWordButton.classList.remove('active');
    }

    stopWakeWordEngine() {
        this._clearWakeWordRestart();
        if (this.wakeWordEngine) {
            try {
                this.wakeWordEngine.onresult = null;
                this.wakeWordEngine.onerror = null;
                this.wakeWordEngine.onend = null;
                this.wakeWordEngine.stop();
            } catch (e) { /* ignore */ }
            this.wakeWordEngine = null;
        }
    }

    async startRecording() {
        if (this.isRecording || !this.isConnected) return;

        // Desativar wake word engine durante gravação para evitar feedback
        if (this.wakeWordActive) {
            this.stopWakeWordEngine();
        }

        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
            });
            if (!this.audioContext) this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            if (this.audioContext.state === 'suspended') await this.audioContext.resume();

            this._initRecording(stream, !this.autoTriggered);
            this.autoTriggered = false;

        } catch (error) {
            console.error('Microphone error:', error.name);
            this.handleError(error.name === 'NotAllowedError' ? 'Permissão de microfone negada' : `Erro: ${error.name}`);
            this.stopRecording();
        }
    }

    async _startRecordingWithStream(stream) {
        if (this.isRecording || !this.isConnected) { stream.getTracks().forEach(t => t.stop()); return; }

        if (this.wakeWordActive) this.stopWakeWordEngine();

        try {
            if (!this.audioContext) this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            if (this.audioContext.state === 'suspended') await this.audioContext.resume();
            this._initRecording(stream, false);
            this.autoTriggered = false;

        } catch (error) {
            console.error('Microphone error:', error.name);
            stream.getTracks().forEach(t => t.stop());
            this.handleError(error.name === 'NotAllowedError' ? 'Permissão de microfone negada' : `Erro: ${error.name}`);
            this.stopRecording();
        }
    }

    _initRecording(stream, playBeep) {
        // Cleanup previous mic source to avoid memory leak
        if (this._micSourceNode) {
            try { this._micSourceNode.disconnect(); } catch (e) {}
            this._micSourceNode = null;
        }

        this.analyser = this.audioContext.createAnalyser();
        this.analyser.fftSize = 256;
        this._micSourceNode = this.audioContext.createMediaStreamSource(stream);
        this._micSourceNode.connect(this.analyser);

        const types = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'];
        let mime = null;
        for (const t of types) { if (MediaRecorder.isTypeSupported(t)) { mime = t; break; } }
        this.mediaRecorder = new MediaRecorder(stream, mime ? { mimeType: mime } : {});
        this.recordedChunks = [];

        this.mediaRecorder.ondataavailable = (ev) => { if (ev.data.size > 0) this.recordedChunks.push(ev.data); };
        this.mediaRecorder.onstop = () => { console.log('MediaRecorder stopped'); this.processRecording(); };
        this._micStream = stream;

        this.mediaRecorder.start(200);
        this.isRecording = true;
        this._awaitingBackend = false;
        this._setPhase('recording', 'microfone aberto');
        this.elements.recordButton.classList.add('recording');
        this.updateStatus('listening');
        this.animateWaveform();
        this._startSilenceDetection();
        if (playBeep) this.playTone(1200, 0.15);
    }

    _stopRecordingSilent() {
        if (!this.isRecording) return;
        if (this._silenceDetectionInterval) { clearInterval(this._silenceDetectionInterval); this._silenceDetectionInterval = null; }
        if (this.mediaRecorder) { this.mediaRecorder.onstop = null; if (this.mediaRecorder.state !== 'inactive') this.mediaRecorder.stop(); }
        if (this._micSourceNode) { try { this._micSourceNode.disconnect(); } catch (e) {} this._micSourceNode = null; }
        if (this._micStream) this._micStream.getTracks().forEach(t => t.stop());
        this.isRecording = false;
        this.elements.recordButton.classList.remove('recording');
        this.stopWaveformAnimation();
        this.recordedChunks = [];
        this._setPhase('idle', 'gravação interrompida');
    }

    _startSilenceDetection() {
        // Reutiliza this.analyser (mesmo nó conectado ao mic source)
        const buf = new Uint8Array(this.analyser.fftSize);
        let silenceStart = null;
        this._silenceDetectionInterval = setInterval(() => {
            if (!this.isRecording) { clearInterval(this._silenceDetectionInterval); return; }
            // Time-domain RMS: mais confiável que frequency data para silence detection
            this.analyser.getByteTimeDomainData(buf);
            let sum = 0;
            for (let i = 0; i < buf.length; i++) {
                const v = buf[i] - 128;
                sum += v * v;
            }
            const rms = Math.sqrt(sum / buf.length);
            if (rms < 8) {
                if (!silenceStart) silenceStart = Date.now();
                else if (Date.now() - silenceStart > 1500) {
                    console.log('Silence detected (rms:', rms.toFixed(1), ')');
                    this.playTone(600, 0.12);
                    this.stopRecording();
                }
             } else { silenceStart = null; }
         }, 100);
     }

    stopTTSPlayback(sendCancel = false) {
        this._clearWakeWordRestart();
        if (this._ttsAudioBuffer) { try { this._ttsAudioBuffer.stop(); } catch (e) {} this._ttsAudioBuffer = null; }
        this._audioQueue = [];
        this._isPlayingQueue = false;
        this._isSpeaking = false;
        this._partialResponseText = '';
        if (sendCancel) this._awaitingBackend = false;
        this._setPhase('idle', sendCancel ? 'interrupção solicitada' : 'tts interrompido');
        this.updateStatus('connected');
        // Only send cancel when explicitly requested (not on every wake word trigger)
        if (sendCancel && this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ action: 'cancel' }));
        }
    }

    stopRecording() {
        if (!this.isRecording) return;
        if (this._silenceDetectionInterval) { clearInterval(this._silenceDetectionInterval); this._silenceDetectionInterval = null; }
        if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') this.mediaRecorder.stop();
        if (this._micSourceNode) { try { this._micSourceNode.disconnect(); } catch (e) {} this._micSourceNode = null; }
        if (this._micStream) this._micStream.getTracks().forEach(t => t.stop());
        this.isRecording = false;
        this._awaitingBackend = true;
        this._setPhase('processing', 'aguardando backend');
        this.elements.recordButton.classList.remove('recording');
        this.stopWaveformAnimation();
        this.updateStatus('processing');
    }

    async processRecording() {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
            this._awaitingBackend = false;
            this._setPhase('idle', 'ws indisponível');
            this.handleError('Não conectado');
            this.resetUI();
            this._scheduleWakeWordRestart(300, 'ws indisponível');
            return;
        }
        if (this.recordedChunks.length === 0) {
            this._awaitingBackend = false;
            this._setPhase('idle', 'sem áudio gravado');
            this.handleError('Nenhum áudio');
            this.resetUI();
            this._scheduleWakeWordRestart(300, 'sem áudio gravado');
            return;
        }
        const blob = new Blob(this.recordedChunks, { type: this.recordedChunks[0].type });
        console.log(`Audio: ${blob.size} bytes`);
        // Convert to ArrayBuffer first to guarantee send ordering on Safari
        const buffer = await blob.arrayBuffer();
        this.ws.send(buffer);
        this.ws.send(JSON.stringify({ action: 'stop' }));
        this.resetUI();
    }

    async playAudioResponseBinary(audioBlob) {
        try {
            // Se voz desabilitada, ignorar áudio binário
            if (!this.voiceResponseEnabled) {
                console.log('[TTS] Voice response disabled, skipping audio playback');
                this._isSpeaking = false;
                this._setPhase('idle', 'resposta por voz desabilitada');
                return;
            }

            let buffer;
            if (audioBlob instanceof Blob) buffer = await audioBlob.arrayBuffer();
            else if (audioBlob instanceof ArrayBuffer) buffer = audioBlob;
            else return;
            if (buffer.byteLength < 50) { console.log('[TTS] Audio too small:', buffer.byteLength, 'bytes'); return; }

            // Queue the audio buffer for sequential playback
            this._audioQueue.push(buffer);
            console.log(`[TTS] Queued audio chunk: ${buffer.byteLength} bytes (queue: ${this._audioQueue.length})`);

            // Start playing if not already
            if (!this._isPlayingQueue) {
                this._playNextInQueue();
            }
        } catch (error) {
            console.error('Playback error:', error);
            this._isSpeaking = false;
            this._setPhase('idle', 'erro ao reproduzir áudio');
            this.updateStatus('connected');
            this._scheduleWakeWordRestart(300, 'erro ao reproduzir áudio');
        }
     }

    async _playNextInQueue() {
        if (this._audioQueue.length === 0) {
            this._isPlayingQueue = false;
            this._ttsAudioBuffer = null;
            this._isSpeaking = false;
            this._setPhase('idle', 'tts concluído');
            this.updateStatus('connected');
            // After all audio played, handle post-playback logic
            setTimeout(() => {
                if (this.isRecording) return;
                if (this._expectingReply) {
                    console.log('[TTS end] Agent expects reply, auto-listening...');
                    this._startConversationListen();
                } else {
                    this._scheduleWakeWordRestart(300, 'tts concluído');
                }
            }, 300);
            return;
        }

        this._isPlayingQueue = true;
        this._isSpeaking = true;
        this._setPhase('tts_playing', 'fila de áudio');
        this.updateStatus('speaking');

        const buffer = this._audioQueue.shift();
        try {
            if (!this.audioContext) this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            if (this.audioContext.state === 'suspended') await this.audioContext.resume();

            const audioBuffer = await this.audioContext.decodeAudioData(buffer.slice(0));
            const source = this.audioContext.createBufferSource();
            source.buffer = audioBuffer;
            // Fade-in/out para evitar glitch MP3
            const gain = this.audioContext.createGain();
            const now = this.audioContext.currentTime;
            const dur = audioBuffer.duration;
            gain.gain.setValueAtTime(0.001, now);
            gain.gain.exponentialRampToValueAtTime(1, now + 0.05);
            gain.gain.setValueAtTime(1, now + Math.max(dur - 0.05, 0.05));
            gain.gain.exponentialRampToValueAtTime(0.001, now + dur);
            source.connect(gain);
            gain.connect(this.audioContext.destination);
            source.start(0);
            this._ttsAudioBuffer = source;

            // Safari: onended may not fire, use timeout fallback
            let called = false;
            const done = () => { if (called) return; called = true; this._playNextInQueue(); };
            const durationMs = Math.ceil(dur * 1000) + 100;
            setTimeout(done, durationMs);
            source.onended = () => done();
        } catch (error) {
            console.error('Queue playback error:', error);
            // Skip this chunk, try next
            this._playNextInQueue();
        }
    }

    async playAudioResponse(d) { return await this.playAudioResponseBinary(d); }
    showTranscription(t) { this.elements.transcription.textContent = t; this.elements.transcription.classList.add('visible'); this.elements.response.classList.remove('visible'); }
    showResponse(t) { this.elements.response.textContent = t; this.elements.response.classList.add('visible'); this.elements.transcription.classList.remove('visible'); }

    updateStatus(status) {
        const map = { connected: ['Conectado', '#00d4ff'], disconnected: ['Desconectado', '#ff4444'], listening: ['Ouvindo', '#00d4ff'], processing: ['Processando', '#ffaa00'], speaking: ['Falando', '#00d4ff'], reconnecting: ['Reconectando', '#ffaa00'], thinking: ['Pensando', '#ffaa00'] };
        const [text, color] = map[status] || [status, '#00d4ff'];
        this.elements.statusText.textContent = text;
        this.elements.statusText.style.color = color;
        this.elements.statusDot.style.backgroundColor = color;
        this.elements.statusDot.style.animation = (status === 'disconnected' || status === 'reconnecting') ? 'none' : 'pulse 2s infinite';
     }

    handleError(msg) {
        this.elements.errorMessage.textContent = msg;
        this.elements.errorMessage.classList.add('visible');
        this.elements.statusDot.style.backgroundColor = '#ff4444';
        this.elements.statusDot.style.animation = 'none';
        setTimeout(() => this.elements.errorMessage.classList.remove('visible'), 5000);
     }

    resetUI() {
        this.elements.transcription.classList.remove('visible');
        this.elements.response.classList.remove('visible');
        this.elements.spinner.classList.remove('visible');
        this.elements.errorMessage.classList.remove('visible');
     }

    animateWaveform() {
        const a = this.analyser, c = this.elements.waveformCanvas, ctx = c.getContext('2d');
        const buf = new Uint8Array(a.frequencyBinCount);
        const anim = () => {
            if (!this.isRecording) return;
            requestAnimationFrame(anim);
            a.getByteFrequencyData(buf);
            ctx.clearRect(0, 0, c.width, c.height);
            const cx = c.width/2, cy = c.height/2, r = 80;
            ctx.beginPath(); ctx.strokeStyle = 'rgba(0,212,255,0.8)'; ctx.lineWidth = 2;
            for (let i = 0; i < buf.length; i++) {
                const angle = (i/buf.length)*Math.PI*2, mag = buf[i]/255;
                const rr = r + mag*40;
                if (i === 0) ctx.moveTo(cx+rr*Math.cos(angle), cy+rr*Math.sin(angle));
                else ctx.lineTo(cx+rr*Math.cos(angle), cy+rr*Math.sin(angle));
             }
            ctx.closePath(); ctx.stroke();
            ctx.beginPath(); ctx.arc(cx,cy,r*0.8,0,Math.PI*2); ctx.fillStyle='rgba(0,212,255,0.1)'; ctx.fill(); ctx.stroke();
         };
        anim();
     }

    stopWaveformAnimation() {
        const c = this.elements.waveformCanvas;
        if (c) c.getContext('2d').clearRect(0, 0, c.width, c.height);
    }

    playTone(freq,dur) {
        if (!this.audioContext) return;
        const o = this.audioContext.createOscillator(), g = this.audioContext.createGain();
        o.connect(g); g.connect(this.audioContext.destination);
        o.frequency.value = freq; o.type = 'sine';
        g.gain.setValueAtTime(0.1, this.audioContext.currentTime);
        g.gain.exponentialRampToValueAtTime(0.001, this.audioContext.currentTime + dur);
        o.start(); o.stop(this.audioContext.currentTime + dur);
     }

    animateParticles() {
        const pc = document.getElementById('particles');
        if (!pc) return;
        for (let i = 0; i < 20; i++) {
            const p = document.createElement('div');
            p.className = 'particle';
            const s = Math.random()*100+50;
            p.style.width = p.style.height = `${s}px`;
            p.style.left = `${Math.random()*100}%`;
            p.style.bottom = `-${s}px`;
            p.style.animationDelay = `${Math.random()*20}s`;
            p.style.animationDuration = `${Math.random()*20+20}s`;
            pc.appendChild(p);
         }
      }

    async preloadAckPhrases(retries = 3) {
        for (let attempt = 0; attempt < retries; attempt++) {
            try {
                const resp = await fetch('/ack/count');
                const { count } = await resp.json();
                if (count === 0) throw new Error('No ack phrases ready');
                this._ackRawBuffers = [];
                for (let i = 0; i < count; i++) {
                    const audioResp = await fetch(`/ack/${i}`);
                    this._ackRawBuffers.push(await audioResp.arrayBuffer());
                }
                console.log(`Preloaded ${this._ackRawBuffers.length} ack phrases`);
                return;
            } catch (e) {
                console.warn(`Ack preload attempt ${attempt + 1} failed:`, e.message);
                if (attempt < retries - 1) await new Promise(r => setTimeout(r, 2000));
            }
        }
    }

    async _speakAcknowledgment(callback) {
        if (!this._ackRawBuffers || this._ackRawBuffers.length === 0) {
            this._isAckPlaying = false;
            this.playTone(1200, 0.15);
            setTimeout(callback, 400);
            return;
        }

        try {
            this._isAckPlaying = true;
            this._setPhase('ack_playing', 'tocando confirmação');
            if (!this.audioContext) this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            if (this.audioContext.state === 'suspended') await this.audioContext.resume();

            const idx = Math.floor(Math.random() * this._ackRawBuffers.length);
            if (!this._ackDecodedBuffers[idx]) {
                this._ackDecodedBuffers[idx] = await this.audioContext.decodeAudioData(this._ackRawBuffers[idx].slice(0));
            }

            const source = this.audioContext.createBufferSource();
            source.buffer = this._ackDecodedBuffers[idx];

            // Fade-in/out para evitar pop/glitch do encoder delay MP3
            const gain = this.audioContext.createGain();
            const now = this.audioContext.currentTime;
            const dur = source.buffer.duration;
            gain.gain.setValueAtTime(0.001, now);
            gain.gain.exponentialRampToValueAtTime(1, now + 0.05);
            gain.gain.setValueAtTime(1, now + dur - 0.05);
            gain.gain.exponentialRampToValueAtTime(0.001, now + dur);
            source.connect(gain);
            gain.connect(this.audioContext.destination);

            let called = false;
            const done = () => {
                if (called) return;
                called = true;
                this._isAckPlaying = false;
                callback();
            };

            // Timeout baseado na duração real do áudio (onended não dispara no Safari)
            const durationMs = Math.ceil(dur * 1000) + 150;
            setTimeout(done, durationMs);
            source.onended = () => done();

            source.start(0);
        } catch (e) {
            console.error('Ack playback error:', e);
            this._isAckPlaying = false;
            this.playTone(1200, 0.15);
            setTimeout(callback, 400);
        }
    }

    _startConversationListen() {
        // Modo conversa contínua: abrir mic diretamente sem wake word
        this._expectingReply = false;
        this.autoTriggered = true;
        this.stopWakeWordEngine();
        this._setPhase('processing', 'aguardando resposta do usuário');
        console.log('[Conversation] Auto-listen started');
        this.playTone(800, 0.1);
        setTimeout(() => this.startRecording(), 200);
    }

    startWakeWordWatchdog() {
        setInterval(() => {
            if (!this._canRunWakeWord()) return;
            if (this.wakeWordEngine === null) {
                console.log('[Watchdog] Wake word engine ausente, reativando...');
                this.enableWakeWord();
            }
        }, 3000);
    }

    async updateIPHint() {
        try {
            const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
            pc.createDataChannel('');
            pc.onicecandidate = (ev) => { if (ev.candidate) { const ip = ev.candidate.address; if (ip && !ip.startsWith('169.254')) this.elements.ipHint.textContent = `ws://${ip}:8765`; } pc.close(); };
            pc.createOffer().then((o) => pc.setLocalDescription(o));
         } catch (e) { this.elements.ipHint.textContent = 'Local server'; }
      }
}

document.addEventListener('DOMContentLoaded', () => { window.jarvisClient = new JarvisVoiceClient(); });
