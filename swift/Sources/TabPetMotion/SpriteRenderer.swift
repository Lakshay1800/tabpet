import TabPetCore

/// One pose layer's drawable state, computed by `SpritePlayer` and handed to
/// a `SpriteRenderer` - everything a view needs except the pixel geometry
/// (contentsRect), which is the renderer's own job.
package struct SpriteLayerState: Equatable, Sendable {
    /// Which cell of this layer's sheet to show - `clamp(round(progress *
    /// (frames - 1)))`, never negative, never past the sheet's last frame.
    package var frame: Int
    /// 0...1. Only ever 0, 1, or mid-fade (the 110ms cross-dissolve).
    package var opacity: Double
    package var z: Int
    /// Only the current pose's layer takes a new facing on a commit - an
    /// outgoing (fading) layer keeps whatever it already had.
    package var facing: Facing
    /// `profile.scale`, folded in identically for every layer alongside the
    /// facing mirror.
    package var scale: Double

    package init(frame: Int, opacity: Double, z: Int, facing: Facing, scale: Double) {
        self.frame = frame
        self.opacity = opacity
        self.z = z
        self.facing = facing
        self.scale = scale
    }
}

/// One full commit's worth of drawable state - the three pose layers, the
/// whole-view press scale, and whether a renderer should ask for a fuller
/// display rate than the current sheet's own fps right now.
package struct SpriteRenderState: Equatable, Sendable {
    package var idle: SpriteLayerState
    package var run: SpriteLayerState
    package var sit: SpriteLayerState
    /// `reduceMotion ? 1 : 1 + pressed * (PRESS_SCALE - 1)`, recomputed
    /// fresh on every commit and every tick a press animation is live.
    package var pressScale: Double
    /// True while a pose fade or the press animation is live - false when
    /// only a frame track (a running sheet, the busy loop) is active.
    package var needsFullFrameRate: Bool

    package init(idle: SpriteLayerState, run: SpriteLayerState, sit: SpriteLayerState, pressScale: Double, needsFullFrameRate: Bool) {
        self.idle = idle
        self.run = run
        self.sit = sit
        self.pressScale = pressScale
        self.needsFullFrameRate = needsFullFrameRate
    }

    package subscript(pose: PupPose) -> SpriteLayerState {
        switch pose {
        case .idle: return idle
        case .run: return run
        case .sit: return sit
        }
    }
}

/// What a `SpritePlayer` draws through - implemented by `CompanionSpriteView`
/// for real drawing, and by a recording renderer in tests. One call per
/// commit and per tick while anything is animating.
@MainActor
package protocol SpriteRenderer: AnyObject {
    func spritePlayer(_ player: SpritePlayer, didRender state: SpriteRenderState)
}

/// One coalesced input to `SpritePlayer.commit(_:)` - mirrors the
/// `pose`/`busy`/`facing`/reduceMotion props `companion-sprite.tsx` reads
/// each render.
package struct SpriteCommit: Equatable, Sendable {
    package var pose: PupPose
    package var busy: Bool
    package var facing: Facing
    package var reduceMotion: Bool

    package init(pose: PupPose = .idle, busy: Bool = false, facing: Facing = .right, reduceMotion: Bool = false) {
        self.pose = pose
        self.busy = busy
        self.facing = facing
        self.reduceMotion = reduceMotion
    }
}
