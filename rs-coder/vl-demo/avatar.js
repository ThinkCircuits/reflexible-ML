/**
 * Avatar Animation Library
 * Provides animated SVG avatar with lip-sync, blinking, thinking expressions
 * For use with Qwen2.5-VL + TTS demo
 */

// ==================== Avatar SVG Template ====================

const AVATAR_SVG_TEMPLATE = `
<defs>
    <!-- Background gradient - soft warm sunset -->
    <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:#4a3c6e"/>
        <stop offset="40%" style="stop-color:#6b4a7a"/>
        <stop offset="70%" style="stop-color:#8a5a6a"/>
        <stop offset="100%" style="stop-color:#c47a6a"/>
    </linearGradient>
    <!-- Soft bokeh/light effect -->
    <radialGradient id="bokeh1" cx="20%" cy="25%" r="30%">
        <stop offset="0%" style="stop-color:#ffffff; stop-opacity:0.15"/>
        <stop offset="100%" style="stop-color:#ffffff; stop-opacity:0"/>
    </radialGradient>
    <radialGradient id="bokeh2" cx="80%" cy="60%" r="25%">
        <stop offset="0%" style="stop-color:#ffd4b8; stop-opacity:0.12"/>
        <stop offset="100%" style="stop-color:#ffd4b8; stop-opacity:0"/>
    </radialGradient>
    <radialGradient id="bokeh3" cx="10%" cy="80%" r="20%">
        <stop offset="0%" style="stop-color:#b8d4ff; stop-opacity:0.1"/>
        <stop offset="100%" style="stop-color:#b8d4ff; stop-opacity:0"/>
    </radialGradient>
    <!-- Gradient for hair -->
    <linearGradient id="hairGradient" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" style="stop-color:#5a3d2b"/>
        <stop offset="50%" style="stop-color:#3d2817"/>
        <stop offset="100%" style="stop-color:#2a1a0f"/>
    </linearGradient>
    <!-- Hair highlight -->
    <linearGradient id="hairHighlight" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" style="stop-color:#6b4c35"/>
        <stop offset="50%" style="stop-color:#7a5a42"/>
        <stop offset="100%" style="stop-color:#6b4c35"/>
    </linearGradient>
    <!-- Gradient for face -->
    <radialGradient id="faceGradient" cx="50%" cy="35%" r="65%">
        <stop offset="0%" style="stop-color:#fce4d4"/>
        <stop offset="70%" style="stop-color:#f0d0b8"/>
        <stop offset="100%" style="stop-color:#e8c4a8"/>
    </radialGradient>
    <!-- Lip gradient -->
    <linearGradient id="lipGradient" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" style="stop-color:#d4847a"/>
        <stop offset="100%" style="stop-color:#b86b62"/>
    </linearGradient>
    <!-- Eye gradient for depth -->
    <radialGradient id="irisGradient" cx="30%" cy="30%" r="70%">
        <stop offset="0%" style="stop-color:#7a9e8a"/>
        <stop offset="100%" style="stop-color:#4a6e5a"/>
    </radialGradient>
    <!-- Blouse/top gradient -->
    <linearGradient id="blouseGradient" x1="0%" y1="0%" x2="0%" y2="100%">
        <stop offset="0%" style="stop-color:#5a7a9a"/>
        <stop offset="50%" style="stop-color:#4a6a8a"/>
        <stop offset="100%" style="stop-color:#3a5a7a"/>
    </linearGradient>
    <!-- Blouse highlight -->
    <linearGradient id="blouseHighlight" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" style="stop-color:#6a8aaa"/>
        <stop offset="50%" style="stop-color:#7a9aba"/>
        <stop offset="100%" style="stop-color:#6a8aaa"/>
    </linearGradient>
</defs>

<!-- Background -->
<rect x="0" y="0" width="120" height="160" fill="url(#bgGradient)"/>
<!-- Soft bokeh lights in background -->
<ellipse cx="25" cy="40" rx="30" ry="30" fill="url(#bokeh1)"/>
<ellipse cx="95" cy="100" rx="25" ry="25" fill="url(#bokeh2)"/>
<ellipse cx="15" cy="140" rx="20" ry="20" fill="url(#bokeh3)"/>
<ellipse cx="100" cy="30" rx="15" ry="15" fill="url(#bokeh1)"/>

<!-- Shoulders - these stay static -->
<g id="shouldersGroup">
    <!-- Long hair behind shoulders (static - starts at head level ~50, connected) -->
    <path d="M22 50 C16 75 14 100 18 135 Q26 152 42 160 L42 160 L36 120 C26 100 24 70 22 50 Z" fill="url(#hairGradient)"/>
    <path d="M98 50 C104 75 106 100 102 135 Q94 152 78 160 L78 160 L84 120 C94 100 96 70 98 50 Z" fill="url(#hairGradient)"/>
    <!-- Hair strands for realism -->
    <path d="M24 58 C20 85 22 115 28 145" stroke="#4a3020" stroke-width="0.8" fill="none" opacity="0.3"/>
    <path d="M28 55 C24 80 25 110 32 140" stroke="#5a4030" stroke-width="0.6" fill="none" opacity="0.25"/>
    <path d="M96 58 C100 85 98 115 92 145" stroke="#4a3020" stroke-width="0.8" fill="none" opacity="0.3"/>
    <path d="M92 55 C96 80 95 110 88 140" stroke="#5a4030" stroke-width="0.6" fill="none" opacity="0.25"/>

    <!-- SKIN: Small area of shoulders/collarbone visible in V-neckline -->
    <path d="M40 136 Q50 134 60 136 Q70 134 80 136 Q72 142 60 145 Q48 142 40 136 Z" fill="url(#faceGradient)"/>
    <!-- Collarbone shadows -->
    <path d="M44 137 Q50 136 56 137" stroke="#dbb8a0" stroke-width="1" fill="none" opacity="0.3"/>
    <path d="M76 137 Q70 136 64 137" stroke="#dbb8a0" stroke-width="1" fill="none" opacity="0.3"/>

    <!-- BLOUSE: Covers shoulders completely with V-neckline -->
    <path d="M-5 160 Q5 142 25 135 Q38 132 45 135 L45 160 Z" fill="url(#blouseGradient)"/>
    <path d="M125 160 Q115 142 95 135 Q82 132 75 135 L75 160 Z" fill="url(#blouseGradient)"/>
    <!-- V-neckline blouse center -->
    <path d="M45 135 Q52 142 60 148 Q68 142 75 135 L75 160 L45 160 Z" fill="url(#blouseGradient)"/>
    <!-- Blouse neckline edge -->
    <path d="M45 135 Q52 142 60 148 Q68 142 75 135" stroke="#4a6a8a" stroke-width="0.8" fill="none" opacity="0.6"/>
    <!-- Shoulder seams -->
    <path d="M28 137 Q15 145 5 152" stroke="#4a6a8a" stroke-width="0.8" fill="none" opacity="0.5"/>
    <path d="M92 137 Q105 145 115 152" stroke="#4a6a8a" stroke-width="0.8" fill="none" opacity="0.5"/>
    <!-- Blouse folds -->
    <path d="M52 148 Q55 155 54 160" stroke="#3a5a7a" stroke-width="1" fill="none" opacity="0.4"/>
    <path d="M68 148 Q65 155 66 160" stroke="#3a5a7a" stroke-width="1" fill="none" opacity="0.4"/>
</g>

<!-- Head group - everything that moves with head -->
<g id="headGroup">
    <!-- Solid hair background - blocks background from showing through head AND neck -->
    <ellipse cx="60" cy="55" rx="42" ry="40" fill="#2a1a0f"/>
    <!-- Hair behind neck area - extends down to cover behind neck -->
    <path d="M25 70 L25 140 Q35 145 60 145 Q85 145 95 140 L95 70 Z" fill="#2a1a0f"/>
    <!-- Hair back/top of head - connects to side hair at ~50 -->
    <path d="M18 50 C18 25 35 15 60 15 C85 15 102 25 102 50 C102 60 96 65 88 68 L32 68 C24 65 18 60 18 50 Z" fill="url(#hairGradient)"/>

    <!-- Ears (partially hidden by hair) -->
    <ellipse cx="26" cy="82" rx="4" ry="7" fill="#f0d0b8"/>
    <ellipse cx="94" cy="82" rx="4" ry="7" fill="#f0d0b8"/>

    <!-- Neck - quick feminine flare to shoulders -->
    <path d="M48 125 C46 128 44 132 42 136 L78 136 C76 132 74 128 72 125" fill="url(#faceGradient)"/>
    <!-- Neck hollow at base -->
    <path d="M55 130 Q58 133 60 135 Q62 133 65 130" stroke="#d4a888" stroke-width="1.2" fill="none" opacity="0.35"/>

    <!-- Face - more defined contour with stronger jawline -->
    <path d="M25 80 Q25 55 60 52 Q95 55 95 80 Q95 100 82 115 Q70 128 60 130 Q50 128 38 115 Q25 100 25 80 Z" fill="url(#faceGradient)" id="faceShape"/>

    <!-- Cheekbone highlights -->
    <path d="M28 85 Q32 78 38 76" stroke="#fce8d8" stroke-width="2" fill="none" opacity="0.3" stroke-linecap="round"/>
    <path d="M92 85 Q88 78 82 76" stroke="#fce8d8" stroke-width="2" fill="none" opacity="0.3" stroke-linecap="round"/>

    <!-- Jaw line shadow - stronger definition -->
    <path d="M28 92 Q32 108 42 118 Q48 124 55 127" stroke="#d0a080" stroke-width="1.5" fill="none" opacity="0.4"/>
    <path d="M92 92 Q88 108 78 118 Q72 124 65 127" stroke="#d0a080" stroke-width="1.5" fill="none" opacity="0.4"/>

    <!-- Chin definition -->
    <path d="M50 125 Q55 129 60 130 Q65 129 70 125" stroke="#dbb8a0" stroke-width="1.2" fill="none" opacity="0.5"/>
    <!-- Chin highlight -->
    <ellipse cx="60" cy="124" rx="6" ry="3" fill="#fce8d8" opacity="0.15"/>

    <!-- Temple shadows -->
    <path d="M28 65 Q30 72 32 78" stroke="#dbb8a0" stroke-width="1" fill="none" opacity="0.3"/>
    <path d="M92 65 Q90 72 88 78" stroke="#dbb8a0" stroke-width="1" fill="none" opacity="0.3"/>

    <!-- Hair - flowing, connected, realistic -->
    <!-- Main bangs/fringe - side swept -->
    <path d="M25 60 C30 40 45 28 60 26 C75 28 90 40 95 60 C90 52 78 46 60 45 C42 46 30 52 25 60 Z" fill="url(#hairGradient)"/>
    <!-- Left side hair - flows down connected to bangs -->
    <path d="M25 60 C22 68 20 80 22 95 C24 110 20 130 18 150 C16 130 18 105 20 85 C21 72 23 64 25 60 Z" fill="url(#hairGradient)"/>
    <!-- Right side hair - flows down connected to bangs -->
    <path d="M95 60 C98 68 100 80 98 95 C96 110 100 130 102 150 C104 130 102 105 100 85 C99 72 97 64 95 60 Z" fill="url(#hairGradient)"/>
    <!-- Hair highlight strands -->
    <path d="M28 62 C26 75 25 95 24 115 C23 130 22 142 20 150" stroke="#6b4c35" stroke-width="1.5" fill="none" opacity="0.5"/>
    <path d="M32 58 C30 72 28 92 27 112" stroke="#7a5a42" stroke-width="1" fill="none" opacity="0.4"/>
    <path d="M92 62 C94 75 95 95 96 115 C97 130 98 142 100 150" stroke="#6b4c35" stroke-width="1.5" fill="none" opacity="0.5"/>
    <path d="M88 58 C90 72 92 92 93 112" stroke="#7a5a42" stroke-width="1" fill="none" opacity="0.4"/>
    <!-- Wispy strands near face -->
    <path d="M30 65 C28 72 27 80 28 88" stroke="#5a3d2b" stroke-width="0.6" fill="none" opacity="0.4"/>
    <path d="M90 65 C92 72 93 80 92 88" stroke="#5a3d2b" stroke-width="0.6" fill="none" opacity="0.4"/>

    <!-- Eyebrows - longer, thicker, realistic with individual hair strokes -->
    <g id="leftBrow">
        <!-- Base brow shape - longer and thicker -->
        <path d="M30 70 Q35 66 42 64.5 Q49 65 54 68" stroke="#4a3c30" stroke-width="2" fill="none" stroke-linecap="round"/>
        <!-- Secondary thickness layer -->
        <path d="M31 69 Q36 65.5 42 64 Q48 65 53 67.5" stroke="#3d3025" stroke-width="1.2" fill="none" opacity="0.6"/>
        <!-- Individual hairs for texture -->
        <path d="M32 70 Q33 67 34 66" stroke="#5d4e42" stroke-width="0.8" fill="none" opacity="0.8"/>
        <path d="M36 68 Q37 65 38 64.5" stroke="#4a3c30" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M40 66.5 Q41 65 42 64.5" stroke="#5d4e42" stroke-width="0.7" fill="none" opacity="0.8"/>
        <path d="M44 66 Q45 65 46 64.5" stroke="#4a3c30" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M48 66 Q49 65.5 50 66" stroke="#5d4e42" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M51 67 Q52 66.5 53 67" stroke="#4a3c30" stroke-width="0.5" fill="none" opacity="0.6"/>
    </g>
    <g id="rightBrow">
        <!-- Base brow shape - longer and thicker -->
        <path d="M66 68 Q71 65 78 64.5 Q85 66 90 70" stroke="#4a3c30" stroke-width="2" fill="none" stroke-linecap="round"/>
        <!-- Secondary thickness layer -->
        <path d="M67 67.5 Q72 65 78 64 Q84 65.5 89 69" stroke="#3d3025" stroke-width="1.2" fill="none" opacity="0.6"/>
        <!-- Individual hairs for texture -->
        <path d="M67 67 Q68 66.5 69 67" stroke="#4a3c30" stroke-width="0.5" fill="none" opacity="0.6"/>
        <path d="M70 66 Q71 65.5 72 66" stroke="#5d4e42" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M74 66 Q75 65 76 64.5" stroke="#4a3c30" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M78 66.5 Q79 65 80 64.5" stroke="#5d4e42" stroke-width="0.7" fill="none" opacity="0.8"/>
        <path d="M82 68 Q83 65 84 64.5" stroke="#4a3c30" stroke-width="0.6" fill="none" opacity="0.7"/>
        <path d="M86 70 Q87 67 88 66" stroke="#5d4e42" stroke-width="0.8" fill="none" opacity="0.8"/>
    </g>

    <!-- Eyes - almond shaped with whites -->
    <ellipse cx="42" cy="78" rx="10" ry="6" fill="#fff" id="leftEyeWhite"/>
    <ellipse cx="78" cy="78" rx="10" ry="6" fill="#fff" id="rightEyeWhite"/>

    <!-- Iris with gradient -->
    <circle cx="42" cy="78" r="4.5" fill="url(#irisGradient)" id="leftIris"/>
    <circle cx="78" cy="78" r="4.5" fill="url(#irisGradient)" id="rightIris"/>

    <!-- Pupils -->
    <circle cx="42" cy="78" r="2.2" fill="#1a1a1a" id="leftPupil"/>
    <circle cx="78" cy="78" r="2.2" fill="#1a1a1a" id="rightPupil"/>

    <!-- Eye highlights -->
    <circle cx="44" cy="76" r="1.3" fill="#fff" opacity="0.9"/>
    <circle cx="80" cy="76" r="1.3" fill="#fff" opacity="0.9"/>

    <!-- Upper eyelids - for blinking animation (positioned at top of eye, expand downward) -->
    <ellipse cx="42" cy="72" rx="10" ry="0" fill="url(#faceGradient)" id="leftEyelid"/>
    <ellipse cx="78" cy="72" rx="10" ry="0" fill="url(#faceGradient)" id="rightEyelid"/>

    <!-- Upper eyelid line/lash line -->
    <path d="M32 74 Q37 71 42 70.5 Q47 71 52 74" stroke="#3d2e22" stroke-width="1.2" fill="none" stroke-linecap="round" id="leftLashLine"/>
    <path d="M68 74 Q73 71 78 70.5 Q83 71 88 74" stroke="#3d2e22" stroke-width="1.2" fill="none" stroke-linecap="round" id="rightLashLine"/>

    <!-- Lower lash line - subtle -->
    <path d="M34 82 Q38 83.5 42 84 Q46 83.5 50 82" stroke="#6d5e52" stroke-width="0.6" fill="none" opacity="0.4"/>
    <path d="M70 82 Q74 83.5 78 84 Q82 83.5 86 82" stroke="#6d5e52" stroke-width="0.6" fill="none" opacity="0.4"/>

    <!-- Nose - subtle, natural -->
    <path d="M60 78 L60 92" stroke="#dbb8a0" stroke-width="1.5" fill="none" stroke-linecap="round"/>
    <path d="M55 95 Q58 97 60 96 Q62 97 65 95" stroke="#dbb8a0" stroke-width="1.2" fill="none" stroke-linecap="round"/>

    <!-- Cheek blush - subtle -->
    <ellipse cx="32" cy="92" rx="8" ry="4" fill="#f0a090" opacity="0.15"/>
    <ellipse cx="88" cy="92" rx="8" ry="4" fill="#f0a090" opacity="0.15"/>

    <!-- Lips - closed position (visible when not speaking) -->
    <g id="closedLips">
        <!-- Upper lip with cupid's bow -->
        <path d="M48 106 Q52 104 56 105 L60 103 L64 105 Q68 104 72 106 Q68 108 60 108 Q52 108 48 106 Z" fill="url(#lipGradient)"/>
        <!-- Lower lip -->
        <path d="M48 106 Q52 108 60 108 Q68 108 72 106 Q70 110 60 111 Q50 110 48 106 Z" fill="#c4736a"/>
    </g>

    <!-- Open mouth group (hidden by default) - lips stay connected at corners -->
    <g id="openMouth" opacity="0">
        <!-- Mouth interior/darkness - smaller opening -->
        <path d="M50 106 Q55 105 60 105 Q65 105 70 106 Q68 112 60 113 Q52 112 50 106 Z" fill="#3a1818" id="mouthInterior"/>

        <!-- Upper teeth - subtle curved row -->
        <path d="M52 106 Q56 105.5 60 105.5 Q64 105.5 68 106 L67 108.5 Q63 108 60 108 Q57 108 53 108.5 Z" fill="#f5f5ec" id="teeth" opacity="0.8"/>

        <!-- Tongue - only visible when wide open -->
        <ellipse cx="60" cy="111" rx="5" ry="2" fill="#c06060" id="tongue" opacity="0"/>

        <!-- Upper lip - stays mostly in place -->
        <path d="M48 106 Q52 104 56 105 L60 103 L64 105 Q68 104 72 106 Q68 106 60 105.5 Q52 106 48 106 Z" fill="url(#lipGradient)" id="upperLipOpen"/>

        <!-- Lower lip - connected at corners (48 and 72), center drops -->
        <path d="M48 106 Q52 110 60 112 Q68 110 72 106 Q70 111 60 113 Q50 111 48 106 Z" fill="#c4736a" id="lowerLipOpen"/>
    </g>

    <!-- Thinking smile - coy asymmetric side-smile -->
    <g id="thinkingSmile" opacity="0">
        <!-- Upper lip - slightly raised on right side -->
        <path d="M48 107 Q54 105 60 104.5 Q66 104 74 102 Q70 106 62 107 Q54 107.5 48 107 Z" fill="url(#lipGradient)"/>
        <!-- Lower lip - follows the asymmetric smile -->
        <path d="M48 107 Q54 107.5 62 107 Q70 106 74 102 Q72 106 64 108.5 Q54 109 48 107 Z" fill="#c4736a"/>
    </g>

</g>
`;

// ==================== Avatar Class ====================

class Avatar {
    constructor(containerSelector) {
        this.container = typeof containerSelector === 'string'
            ? document.querySelector(containerSelector)
            : containerSelector;

        if (!this.container) {
            throw new Error('Avatar container not found');
        }

        // State
        this.audioContext = null;
        this.analyser = null;
        this.animationFrameId = null;
        this.blinkAnimationId = null;
        this.idleAnimationId = null;
        this.nextBlinkTime = 0;
        this.isBlinking = false;
        this.isThinking = false;
        this.isPlaying = false;
        this.useAudioAnalyser = true;
        this.audioSourceMap = new WeakMap();
        this.audioContextResumed = false;

        // Create SVG element
        this._createSVG();

        // Cache DOM elements
        this._cacheElements();

        // Start idle animations
        this.startIdleAnimation();
        this.startBlinkAnimation();
    }

    _createSVG() {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('class', 'avatar-svg');
        svg.setAttribute('viewBox', '0 0 120 160');
        svg.setAttribute('id', 'avatarSvg');
        svg.innerHTML = AVATAR_SVG_TEMPLATE;
        this.container.innerHTML = '';
        this.container.appendChild(svg);
        this.svg = svg;
    }

    _cacheElements() {
        this.headGroup = this.svg.getElementById('headGroup');
        this.closedLips = this.svg.getElementById('closedLips');
        this.openMouth = this.svg.getElementById('openMouth');
        this.thinkingSmile = this.svg.getElementById('thinkingSmile');
        this.mouthInterior = this.svg.getElementById('mouthInterior');
        this.teeth = this.svg.getElementById('teeth');
        this.tongue = this.svg.getElementById('tongue');
        this.lowerLipOpen = this.svg.getElementById('lowerLipOpen');
        this.leftPupil = this.svg.getElementById('leftPupil');
        this.rightPupil = this.svg.getElementById('rightPupil');
        this.leftIris = this.svg.getElementById('leftIris');
        this.rightIris = this.svg.getElementById('rightIris');
        this.leftEyelid = this.svg.getElementById('leftEyelid');
        this.rightEyelid = this.svg.getElementById('rightEyelid');
        this.leftEyeWhite = this.svg.getElementById('leftEyeWhite');
        this.rightEyeWhite = this.svg.getElementById('rightEyeWhite');
    }

    // ==================== Audio Context ====================

    initAudioContext() {
        if (!this.audioContext) {
            this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            this.analyser = this.audioContext.createAnalyser();
            this.analyser.fftSize = 256;
            this.analyser.smoothingTimeConstant = 0.7;
        }
    }

    async resumeAudioContext() {
        if (this.audioContext && this.audioContext.state === 'suspended') {
            try {
                await this.audioContext.resume();
                this.audioContextResumed = true;
            } catch (e) {
                console.error('Failed to resume AudioContext:', e);
            }
        }
    }

    // Connect an audio element to the analyser for lip-sync
    connectAudioElement(audioElement) {
        if (!this.audioSourceMap.has(audioElement)) {
            try {
                this.initAudioContext();
                audioElement.crossOrigin = 'anonymous';
                const source = this.audioContext.createMediaElementSource(audioElement);
                source.connect(this.analyser);
                this.analyser.connect(this.audioContext.destination);
                this.audioSourceMap.set(audioElement, source);
                return true;
            } catch (e) {
                console.warn('Could not connect audio to analyser:', e);
                return false;
            }
        }
        return true;
    }

    // ==================== Blinking Animation ====================

    startBlinkAnimation() {
        if (!this.blinkAnimationId) {
            this.nextBlinkTime = Date.now() + 1000 + Math.random() * 2000;
            this._animateBlink();
        }
    }

    stopBlinkAnimation() {
        if (this.blinkAnimationId) {
            cancelAnimationFrame(this.blinkAnimationId);
            this.blinkAnimationId = null;
        }
        this.leftEyelid.setAttribute('ry', '0');
        this.rightEyelid.setAttribute('ry', '0');
        this.isBlinking = false;
    }

    _animateBlink() {
        const now = Date.now();

        // Skip blinking during thinking
        if (this.isThinking) {
            this.blinkAnimationId = requestAnimationFrame(() => this._animateBlink());
            return;
        }

        if (now >= this.nextBlinkTime && !this.isBlinking) {
            this.isBlinking = true;
            const isDoubleBlink = Math.random() < 0.2;
            this._animateBlinkCycle(isDoubleBlink);
        }

        this.blinkAnimationId = requestAnimationFrame(() => this._animateBlink());
    }

    _animateBlinkCycle(doubleBlink = false) {
        const blinkDuration = 120;
        const holdDuration = 40;
        const startTime = Date.now();
        const eyelidTopY = 72;
        const eyelidClosedY = 78;
        const maxRy = 6;

        const blinkFrame = () => {
            const elapsed = Date.now() - startTime;
            const totalCycle = blinkDuration * 2 + holdDuration;

            let progress;
            if (elapsed < blinkDuration) {
                const t = elapsed / blinkDuration;
                progress = t * t;
            } else if (elapsed < blinkDuration + holdDuration) {
                progress = 1;
            } else if (elapsed < totalCycle) {
                const t = (elapsed - blinkDuration - holdDuration) / blinkDuration;
                progress = 1 - t * t;
            } else {
                this.leftEyelid.setAttribute('cy', eyelidTopY.toString());
                this.rightEyelid.setAttribute('cy', eyelidTopY.toString());
                this.leftEyelid.setAttribute('ry', '0');
                this.rightEyelid.setAttribute('ry', '0');

                if (doubleBlink) {
                    setTimeout(() => this._animateBlinkCycle(false), 80);
                } else {
                    this.isBlinking = false;
                    const baseInterval = 3000 + Math.random() * 3000;
                    const variation = (Math.random() - 0.5) * 1000;
                    this.nextBlinkTime = Date.now() + baseInterval + variation;
                }
                return;
            }

            const eyelidCy = eyelidTopY + (eyelidClosedY - eyelidTopY) * progress;
            const eyelidRy = maxRy * progress;

            this.leftEyelid.setAttribute('cy', eyelidCy.toFixed(1));
            this.rightEyelid.setAttribute('cy', eyelidCy.toFixed(1));
            this.leftEyelid.setAttribute('ry', eyelidRy.toFixed(1));
            this.rightEyelid.setAttribute('ry', eyelidRy.toFixed(1));

            requestAnimationFrame(blinkFrame);
        };

        blinkFrame();
    }

    // ==================== Idle Animation ====================

    startIdleAnimation() {
        if (!this.idleAnimationId) {
            this._animateIdle();
        }
    }

    stopIdleAnimation() {
        if (this.idleAnimationId) {
            cancelAnimationFrame(this.idleAnimationId);
            this.idleAnimationId = null;
        }
    }

    _animateIdle() {
        if (this.isPlaying || this.isThinking) {
            this.idleAnimationId = requestAnimationFrame(() => this._animateIdle());
            return;
        }

        const time = Date.now() / 1000;

        const headX = Math.sin(time * 0.3) * 0.8 + Math.sin(time * 0.7) * 0.4;
        const headY = Math.cos(time * 0.25) * 0.5 + Math.cos(time * 0.6) * 0.3;
        const headRotate = Math.sin(time * 0.2) * 1.2;
        this.headGroup.setAttribute('transform', `translate(${headX}, ${headY}) rotate(${headRotate}, 60, 90)`);

        const eyeX = Math.sin(time * 0.5) * 1.5 + Math.sin(time * 1.3) * 0.5;
        const eyeY = Math.cos(time * 0.4) * 0.8 + Math.cos(time * 1.1) * 0.3;

        this._setEyePosition(eyeX, eyeY);

        this.idleAnimationId = requestAnimationFrame(() => this._animateIdle());
    }

    _setEyePosition(x, y) {
        this.leftIris.setAttribute('cx', 42 + x);
        this.leftIris.setAttribute('cy', 78 + y);
        this.leftPupil.setAttribute('cx', 42 + x);
        this.leftPupil.setAttribute('cy', 78 + y);
        this.rightIris.setAttribute('cx', 78 + x);
        this.rightIris.setAttribute('cy', 78 + y);
        this.rightPupil.setAttribute('cx', 78 + x);
        this.rightPupil.setAttribute('cy', 78 + y);
    }

    _resetEyes() {
        this._setEyePosition(0, 0);
    }

    // ==================== Thinking Animation ====================

    startThinking() {
        this.isThinking = true;
        this.closedLips.setAttribute('opacity', '0');
        this.thinkingSmile.setAttribute('opacity', '1');
        this.leftEyeWhite.setAttribute('ry', '4');
        this.rightEyeWhite.setAttribute('ry', '4');
        this._animateThinking();
    }

    stopThinking() {
        this.isThinking = false;
        this.thinkingSmile.setAttribute('opacity', '0');
        this.closedLips.setAttribute('opacity', '1');
        this.leftEyeWhite.setAttribute('ry', '6');
        this.rightEyeWhite.setAttribute('ry', '6');
        this.headGroup.setAttribute('transform', '');
        this._resetEyes();
    }

    _animateThinking() {
        if (!this.isThinking) return;

        const time = Date.now() / 1000;

        const headX = Math.sin(time * 0.25) * 0.6;
        const headY = Math.cos(time * 0.2) * 0.4;
        const headRotate = Math.sin(time * 0.18) * 1.2;
        this.headGroup.setAttribute('transform', `translate(${headX}, ${headY}) rotate(${headRotate}, 60, 90)`);

        const eyeX = 1.2 + Math.sin(time * 0.35) * 0.6;
        const eyeY = -1 + Math.sin(time * 0.4) * 0.3;
        this._setEyePosition(eyeX, eyeY);

        const eyeNarrow = 4 + Math.sin(time * 0.5) * 0.2;
        this.leftEyeWhite.setAttribute('ry', eyeNarrow.toFixed(1));
        this.rightEyeWhite.setAttribute('ry', eyeNarrow.toFixed(1));

        if (this.isThinking) {
            requestAnimationFrame(() => this._animateThinking());
        }
    }

    // ==================== Speaking Animation ====================

    startSpeaking(withAnalyser = true) {
        this.isPlaying = true;
        this.useAudioAnalyser = withAnalyser;
        if (!this.animationFrameId) {
            this._animateMouth();
        }
    }

    stopSpeaking() {
        this.isPlaying = false;
        if (this.animationFrameId) {
            cancelAnimationFrame(this.animationFrameId);
            this.animationFrameId = null;
        }
        this.closedLips.setAttribute('opacity', '1');
        this.openMouth.setAttribute('opacity', '0');
        this._resetEyes();
    }

    _animateMouth() {
        const time = Date.now() / 1000;

        if (!this.isPlaying) {
            this.closedLips.setAttribute('opacity', '1');
            this.openMouth.setAttribute('opacity', '0');
            this.headGroup.setAttribute('transform', '');
            return;
        }

        let amplitude;

        if (this.useAudioAnalyser && this.analyser) {
            const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
            this.analyser.getByteFrequencyData(dataArray);

            let sum = 0;
            const speechBins = Math.floor(this.analyser.frequencyBinCount * 0.4);
            for (let i = 0; i < speechBins; i++) {
                sum += dataArray[i];
            }
            const average = sum / speechBins;
            amplitude = Math.min(average / 110, 1);
        } else {
            // Fallback animation
            amplitude = Math.abs(
                Math.sin(time * 8) * 0.3 +
                Math.sin(time * 12.5) * 0.25 +
                Math.sin(time * 17) * 0.15 +
                Math.sin(time * 23) * 0.1
            ) * 0.8;
            const pauseFactor = Math.sin(time * 2) > 0.7 ? 0.2 : 1.0;
            amplitude *= pauseFactor;
        }

        // Head movement
        const headTiltX = Math.sin(time * 0.7) * 1.5;
        const headTiltY = Math.cos(time * 0.5) * 0.8;
        const headRotate = Math.sin(time * 0.4) * 2;
        this.headGroup.setAttribute('transform', `translate(${headTiltX}, ${headTiltY}) rotate(${headRotate}, 60, 80)`);

        // Mouth animation
        if (amplitude > 0.08) {
            this.closedLips.setAttribute('opacity', '0');
            this.openMouth.setAttribute('opacity', '1');

            const openY = amplitude * 4;

            const interiorPath = `M50 106 Q55 105 60 105 Q65 105 70 106 Q68 ${109 + openY * 0.6} 60 ${110 + openY} Q52 ${109 + openY * 0.6} 50 106 Z`;
            this.mouthInterior.setAttribute('d', interiorPath);

            const centerDrop = openY * 0.9;
            const lowerLipPath = `M48 106 Q52 ${108 + centerDrop * 0.5} 60 ${109 + centerDrop} Q68 ${108 + centerDrop * 0.5} 72 106 Q70 ${108 + centerDrop * 0.4} 60 ${110 + openY} Q50 ${108 + centerDrop * 0.4} 48 106 Z`;
            this.lowerLipOpen.setAttribute('d', lowerLipPath);

            this.tongue.setAttribute('cy', 109 + openY * 0.5);
            this.tongue.setAttribute('ry', 1.5 + openY * 0.2);
            this.tongue.setAttribute('opacity', amplitude > 0.4 ? Math.min((amplitude - 0.4) * 1.5, 0.7).toFixed(2) : '0');

            this.teeth.setAttribute('opacity', amplitude > 0.15 ? Math.min(amplitude * 0.5, 0.5).toFixed(2) : '0');
        } else {
            this.closedLips.setAttribute('opacity', '1');
            this.openMouth.setAttribute('opacity', '0');
        }

        // Eye movement while speaking
        const eyeBaseX = Math.sin(time * 0.8) * 2 + Math.sin(time * 2.1) * 0.5;
        const eyeBaseY = Math.cos(time * 0.6) * 1 + Math.cos(time * 1.7) * 0.3;
        this._setEyePosition(eyeBaseX, eyeBaseY);

        this.animationFrameId = requestAnimationFrame(() => this._animateMouth());
    }

    // ==================== Cleanup ====================

    destroy() {
        this.stopBlinkAnimation();
        this.stopIdleAnimation();
        this.stopSpeaking();
        this.stopThinking();
        if (this.audioContext) {
            this.audioContext.close();
        }
        this.container.innerHTML = '';
    }
}

// Export for use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { Avatar, AVATAR_SVG_TEMPLATE };
} else {
    window.Avatar = Avatar;
    window.AVATAR_SVG_TEMPLATE = AVATAR_SVG_TEMPLATE;
}
