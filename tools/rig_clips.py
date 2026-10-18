"""Animation clips for Tripo's biped and quadruped rigs, authored with rig_poser.Poser.

Tripo's own preset clips do not suit a game: idle runs 15 s, hurt 14 s and slash 6.5 s, and
each one plays a different full-body routine. These clips are short and loop where they should.
Every clip starts and ends on the same pose when it loops, and every pose is built around
[Biped.stand], so they blend into each other without a snap.

Lengths are in the model's own units, where the model is about 1 unit tall. The game scales a
model to 1.8 m, so a unit is 1.8 m.
"""

import numpy as np

LEGS = {"L": ("L_Thigh", "L_Calf", "L_Foot"), "R": ("R_Thigh", "R_Calf", "R_Foot")}
TORSO = ("Waist", "Spine01", "Spine02")
NECK = ("NeckTwist01", "Head")
ARMS = {"L": ("L_Upperarm", "L_Forearm", "L_Hand"), "R": ("R_Upperarm", "R_Forearm", "R_Hand")}

# name: (duration in seconds, loops)
CLIPS = {
    "idle": (3.2, True),
    "walk": (1.0, True),
    "run": (0.56, True),
    "slash": (0.6, False),
    "hurt": (0.5, False),
    "greet": (1.8, False),
}
# The beast's own timings: it trots rather than runs, and "slash" is a bite.
QUADRUPED_CLIPS = {
    "idle": (2.4, True),
    "walk": (0.9, True),
    "run": (0.5, True),
    "slash": (0.55, False),
    "hurt": (0.45, False),
}

# Tripo names the quadruped bones by chain, not by role. These were matched by position: the
# front legs hang from the head chain and the hind legs from the first spine bone. Left is +X
# when the beast faces +Z.
QUADRUPED_LEGS = {
    "FL": ["bone_22"] + ["tripo::0_Left_Limb_%d" % i for i in range(4)],
    "FR": ["bone_%d" % i for i in range(17, 22)],
    "HL": ["tripo::0_Right_Limb_%d" % i for i in range(5)],
    "HR": ["tripo::1_Right_Limb_%d" % i for i in range(5)],
}
QUADRUPED_SPINE = ("tripo::Spine_0", "tripo::Spine_1", "tripo::Spine_2")
QUADRUPED_HEAD = ("tripo::Head_0", "tripo::Head_1", "tripo::Head_2")
QUADRUPED_TAIL = (
    "bone_39",
    "bone_40",
    "tripo::Tail_0",
    "tripo::Tail_1",
    "tripo::1_Left_Limb_0",
    "tripo::1_Left_Limb_1",
    "tripo::1_Left_Limb_2",
)


def ease(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def blend(keys, time):
    """Interpolates between (time, value) keys with smooth steps. Values may be arrays."""
    if time <= keys[0][0]:
        return np.asarray(keys[0][1], float)
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if time <= t1:
            f = ease((time - t0) / (t1 - t0))
            return np.asarray(a, float) * (1 - f) + np.asarray(b, float) * f
    return np.asarray(keys[-1][1], float)


class Biped:
    def __init__(self, poser):
        self.poser = poser
        pos = poser.pos
        self.ankle_height = 0.5 * (pos("L_Foot")[1] + pos("R_Foot")[1])
        self.stand_feet = {}
        for side in "LR":
            thigh = pos(side + "_Thigh")
            lateral = np.dot(thigh, poser.left) + (0.012 if side == "L" else -0.012)
            self.stand_feet[side] = (
                poser.forward * np.dot(thigh, poser.forward)
                + poser.up * self.ankle_height
                + poser.left * lateral
            )

    def vec(self, forward=0.0, up=0.0, left=0.0):
        p = self.poser
        return p.forward * forward + p.up * up + p.left * left

    def build(
        self,
        hip=(0.0, 0.0, 0.0),
        hip_rot=None,
        pelvis_yaw=0.0,
        pelvis_roll=0.0,
        torso=(0.0, 0.0, 0.0),
        head=(0.0, 0.0, 0.0),
        feet=None,
        arms=None,
        arm_dirs=None,
        hand_roll=None,
    ):
        """One pose. Angles are radians.

        hip      (forward, up, left) offset of the hips
        hip_rot  extra rotation of the whole body about the hips
        torso    (lean forward, turn left, sway left) shared by the three spine bones
        head     (nod down, turn left, tilt left) shared by the neck and head
        feet     {side: (forward, up, left, pitch)} ankle offset from the standing stance
        arms     {side: (abduct, swing, elbow, wrist)} arm hanging at the side
        arm_dirs {side: (upper, forearm, hand)} explicit directions in the body frame
        """
        p = self.poser
        feet = feet or {}
        arms = arms or {}
        hip_rot = np.eye(3) if hip_rot is None else hip_rot
        rotate = {"Hip": hip_rot, "Pelvis": p.twist(pelvis_yaw) @ p.sway(pelvis_roll)}
        lean, yaw, sway = torso
        share = p.twist(yaw / 3) @ p.sway(sway / 3) @ p.lean(lean / 3)
        body = hip_rot.copy()
        for name in TORSO:
            rotate[name] = share
            body = share @ body
        nod, turn, tilt = head
        neck_share = p.twist(turn / 2) @ p.sway(tilt / 2) @ p.lean(nod / 2)
        for name in NECK:
            rotate[name] = neck_share

        aim = {}
        for side in "LR":
            if arm_dirs and side in arm_dirs:
                upper, fore, hand = arm_dirs[side]
            else:
                abduct, swing, elbow, wrist = arms.get(side, (0.38, 0.05, 0.2, 0.0))
                upper = p.limb(side, abduct, swing)
                fore = p.limb(side, abduct * 0.7, swing + elbow)
                hand = p.limb(side, abduct * 0.5, swing + elbow + wrist)
            names = ARMS[side]
            aim[names[0]] = body @ np.asarray(upper, float)
            aim[names[1]] = body @ np.asarray(fore, float)
            aim[names[2]] = body @ np.asarray(hand, float)

        targets = {}
        for side in "LR":
            forward, up, left, pitch = feet.get(side, (0.0, 0.0, 0.0, 0.0))
            targets[side] = (self.stand_feet[side] + self.vec(forward, up, left), pitch)
        return p.pose(
            rotate=rotate,
            aim=aim,
            offset={"Hip": self.vec(*hip)},
            feet=targets,
            legs=LEGS,
        )

    def stand(self):
        return self.build()

    # --- looping clips ---------------------------------------------------------------------

    def idle(self, phase):
        breath = np.sin(2 * np.pi * phase)
        shift = np.sin(2 * np.pi * phase + 0.6)
        return self.build(
            hip=(0.0, -0.004 + 0.002 * breath, 0.006 * shift),
            pelvis_roll=0.012 * shift,
            torso=(0.012 * breath, 0.02 * shift, -0.012 * shift),
            head=(-0.01 * breath, 0.05 * np.sin(2 * np.pi * phase * 2 + 1.0), 0.0),
            arms={
                "L": (0.38 + 0.012 * breath, 0.05, 0.22 + 0.02 * breath, 0.0),
                "R": (0.38 + 0.012 * breath, 0.05, 0.22 + 0.02 * breath, 0.0),
            },
        )

    def _gait(self, phase, beta, step, lift, bob, crouch, arm_swing, elbow, lean, pelvis, torso):
        """A locomotion cycle. The left foot lands at phase 0, the right foot at phase 0.5."""
        feet = {}
        for side, offset in (("L", 0.0), ("R", 0.5)):
            p = (phase + 1.0 - offset) % 1.0
            if p < beta:
                u = p / beta
                forward = step / 2 - step * u
                up = 0.05 * u**4
                pitch = 0.25 * (1 - u) ** 2 - 0.7 * u**4
            else:
                u = (p - beta) / (1 - beta)
                forward = -step / 2 + step * ease(u)
                up = 0.05 * (1 - u) ** 4 + lift * np.sin(np.pi * u**0.8) ** 1.3
                pitch = -0.7 * (1 - u) ** 2 + 0.25 * ease(u)
            feet[side] = (forward, up, 0.0, pitch)
        c = np.cos(2 * np.pi * phase)
        s = np.sin(2 * np.pi * phase)
        # Phase 0 has the left foot forward and the right arm forward.
        bounce = np.cos(4 * np.pi * (phase - beta / 2))
        hip_up = crouch + bob * bounce
        swing = arm_swing * c
        return self.build(
            hip=(0.0, hip_up, 0.0),
            hip_rot=self.poser.lean(lean),
            pelvis_yaw=-pelvis * c,
            pelvis_roll=0.025 * np.sin(2 * np.pi * (phase - beta / 2)),
            torso=(0.0, torso * c, 0.01 * s),
            head=(-lean * 0.8, -torso * 0.6 * c, 0.0),
            feet=feet,
            arms={
                "L": (0.2, -swing, elbow + 0.3 * max(-c, 0.0) * elbow, 0.0),
                "R": (0.2, swing, elbow + 0.3 * max(c, 0.0) * elbow, 0.0),
            },
        )

    def walk(self, phase):
        return self._gait(phase, 0.62, 0.40, 0.045, 0.02, -0.022, 0.45, 0.25, 0.04, 0.10, 0.12)

    def run(self, phase):
        return self._gait(phase, 0.36, 0.62, 0.15, -0.025, -0.06, 0.8, 1.35, 0.16, 0.14, 0.22)

    # --- one-shot clips --------------------------------------------------------------------

    def _dir(self, forward, up, left):
        vector = self.vec(forward, up, left)
        return vector / np.linalg.norm(vector)

    def slash(self, phase):
        """A right-handed diagonal cut: wind up behind the right shoulder, cut across the body."""
        p = self.poser
        wind = blend([(0.0, 0), (0.25, 1), (0.34, 1), (0.5, 0), (1.0, 0)], phase)
        cut = blend([(0.0, 0), (0.34, 0), (0.46, 1), (0.62, 1), (1.0, 0)], phase)
        lunge = blend([(0.0, 0), (0.34, 0), (0.46, 1), (0.72, 1), (1.0, 0)], phase)
        hang = p.limb("R", 0.38, 0.05)
        hang_fore = p.limb("R", 0.27, 0.27)
        upper = blend(
            [
                (0.0, hang),
                (0.25, self._dir(-0.25, 0.8, -0.5)),
                (0.34, self._dir(-0.25, 0.8, -0.5)),
                (0.46, self._dir(0.7, 0.1, 0.25)),
                (0.62, self._dir(0.7, 0.1, 0.25)),
                (1.0, hang),
            ],
            phase,
        )
        fore = blend(
            [
                (0.0, hang_fore),
                (0.25, self._dir(0.1, 0.9, 0.2)),
                (0.34, self._dir(0.1, 0.9, 0.2)),
                (0.46, self._dir(0.3, 0.2, 0.9)),
                (0.62, self._dir(0.3, 0.2, 0.9)),
                (1.0, hang_fore),
            ],
            phase,
        )
        balance = p.limb("L", 0.9, 0.25)
        left_arm = blend(
            [(0.0, p.limb("L", 0.38, 0.05)), (0.3, balance), (1.0, p.limb("L", 0.38, 0.05))], phase
        )
        turn = -0.4 * wind + 0.5 * cut
        return self.build(
            hip=(0.08 * lunge, -0.04 * lunge - 0.01 * wind, 0.0),
            hip_rot=p.twist(-0.3 * wind + 0.4 * cut) @ p.lean(0.1 * cut),
            torso=(0.14 * cut, turn, 0.0),
            head=(0.0, -0.4 * turn, 0.0),
            feet={
                "L": (0.2 * lunge, 0.0, 0.0, 0.0),
                "R": (-0.1 * lunge, 0.0, 0.0, -0.25 * lunge),
            },
            arm_dirs={
                "R": (upper, fore, fore),
                "L": (left_arm, left_arm, left_arm),
            },
        )

    def hurt(self, phase):
        """A short recoil: the chest snaps back and the arms fly out, then settle."""
        p = self.poser
        hit = blend([(0.0, 0), (0.18, 1), (0.45, 0.45), (1.0, 0)], phase)
        return self.build(
            hip=(-0.05 * hit, -0.04 * hit, 0.0),
            hip_rot=p.lean(-0.12 * hit),
            torso=(-0.28 * hit, 0.0, 0.1 * hit),
            head=(-0.3 * hit, 0.0, 0.0),
            feet={"L": (0.06 * hit, 0.0, 0.0, 0.0), "R": (-0.1 * hit, 0.0, 0.0, 0.0)},
            arms={
                "L": (0.38 + 0.7 * hit, 0.05 - 0.2 * hit, 0.22 + 0.2 * hit, 0.0),
                "R": (0.38 + 0.7 * hit, 0.05 - 0.2 * hit, 0.22 + 0.2 * hit, 0.0),
            },
        )

    def greet(self, phase):
        """A fist-and-palm salute with a short bow."""
        p = self.poser
        raised = blend([(0.0, 0), (0.25, 1), (0.8, 1), (1.0, 0)], phase)
        bow = blend([(0.0, 0), (0.3, 0), (0.5, 1), (0.65, 1), (0.85, 0), (1.0, 0)], phase)
        arms = {}
        for side in "LR":
            across = 1.0 if side == "L" else -1.0
            upper = p.limb(side, 0.38, 0.05) * (1 - raised) + p.limb(side, 0.25, 0.5) * raised
            fore = p.limb(side, 0.27, 0.27) * (1 - raised) + (
                self._dir(0.6, 0.25, -0.75 * across) * raised
            )
            upper = upper / np.linalg.norm(upper)
            fore = fore / np.linalg.norm(fore)
            arms[side] = (upper, fore, fore)
        return self.build(
            hip=(0.0, -0.01 * bow, 0.0),
            torso=(0.35 * bow, 0.0, 0.0),
            head=(0.1 * bow, 0.0, 0.0),
            arm_dirs=arms,
        )


class Quadruped:
    """Clips for the demon wolf. Legs are driven by joint angles, since the rig's bind pose is
    already a clean stand with vertical legs."""

    def __init__(self, poser):
        self.poser = poser

    def stand(self):
        return self.poser.pose()

    def build(self, bob=0.0, spine=(0.0, 0.0), head=(0.0, 0.0), tail=(0.0, 0.0), legs=None):
        """One pose.

        bob    height of the whole body
        spine  (dip forward, turn left) shared by the three spine bones
        head   (nod down, turn left) shared by the three head bones
        tail   (raise, sway left) shared by the tail chain
        legs   {leg: (upper, middle, lower, paw)} forward swing of each segment in radians
        """
        p = self.poser
        legs = legs or {}
        rotate = {}
        arch, turn = spine
        for name in QUADRUPED_SPINE:
            rotate[name] = p.twist(turn / 3) @ p.lean(arch / 3)
        nod, look = head
        for name in QUADRUPED_HEAD:
            rotate[name] = p.twist(look / 3) @ p.lean(nod / 3)
        raise_, sway = tail
        for name in QUADRUPED_TAIL:
            rotate[name] = p.twist(sway / len(QUADRUPED_TAIL)) @ p.lean(
                raise_ / len(QUADRUPED_TAIL)
            )
        for leg, bones in QUADRUPED_LEGS.items():
            angles = legs.get(leg, (0.0, 0.0, 0.0, 0.0))
            # A leg does not follow the head or the tail, only the spine it hangs from.
            base = "tripo::Spine_2" if leg in ("FL", "FR") else "tripo::Spine_0"
            for index, name in enumerate(bones):
                if index == 0:
                    rotate[name] = (p.swing(angles[0]), base)
                elif index < len(angles):
                    rotate[name] = p.swing(angles[index])
        return p.pose(rotate=rotate, offset={"tripo::Root": self.vec(up=bob)})

    def vec(self, forward=0.0, up=0.0, left=0.0):
        p = self.poser
        return p.forward * forward + p.up * up + p.left * left

    def _trot(self, phase, swing, lift, bob, spine_arch):
        """Diagonal pairs move together: front left with hind right, then the other pair."""
        legs = {}
        for leg, offset in (("FL", 0.0), ("HR", 0.0), ("FR", 0.5), ("HL", 0.5)):
            p = (phase + 1.0 - offset) % 1.0
            reach = np.cos(2 * np.pi * p)
            # The paw lifts while the leg swings forward, in the second half of the cycle.
            lifted = np.sin(np.pi * (2 * p - 1)) ** 2 if p >= 0.5 else 0.0
            if leg[0] == "F":
                legs[leg] = (
                    swing * reach,
                    -lift * lifted,
                    -0.5 * lift * lifted,
                    0.4 * lift * lifted,
                )
            else:
                legs[leg] = (
                    swing * reach,
                    -lift * lifted,
                    0.9 * lift * lifted,
                    -0.5 * lift * lifted,
                )
        wave = np.sin(4 * np.pi * phase)
        return self.build(
            bob=bob * np.cos(4 * np.pi * phase),
            spine=(spine_arch * wave, 0.06 * np.sin(2 * np.pi * phase)),
            head=(-0.05 * wave, -0.1 * np.sin(2 * np.pi * phase)),
            tail=(0.1, 0.35 * np.sin(2 * np.pi * phase + 1.0)),
            legs=legs,
        )

    def idle(self, phase):
        breath = np.sin(2 * np.pi * phase)
        return self.build(
            bob=0.002 * breath,
            spine=(0.03 * breath, 0.02 * np.sin(2 * np.pi * phase * 2)),
            head=(0.03 + 0.03 * breath, 0.25 * np.sin(2 * np.pi * phase + 0.5)),
            tail=(0.05, 0.3 * np.sin(2 * np.pi * phase * 2)),
        )

    def walk(self, phase):
        return self._trot(phase, 0.38, 0.55, 0.006, 0.03)

    def run(self, phase):
        return self._trot(phase, 0.6, 0.8, 0.012, 0.08)

    def slash(self, phase):
        """A bite: the wolf draws back, lunges head first and snaps, then recovers."""
        crouch = blend([(0.0, 0), (0.3, 1), (0.4, 1), (0.55, 0), (1.0, 0)], phase)
        lunge = blend([(0.0, 0), (0.3, 0), (0.5, 1), (0.65, 1), (1.0, 0)], phase)
        reach = (0.3 * lunge, 0.0, 0.0, 0.0)
        return self.build(
            bob=-0.03 * crouch + 0.02 * lunge,
            spine=(0.12 * lunge - 0.08 * crouch, 0.0),
            head=(0.4 * lunge - 0.25 * crouch, 0.0),
            tail=(0.3 * lunge, 0.2 * crouch),
            legs={
                "FL": (-0.5 * crouch + 0.55 * lunge, 0.3 * lunge, 0.0, 0.0),
                "FR": (-0.5 * crouch + 0.55 * lunge, 0.3 * lunge, 0.0, 0.0),
                "HL": reach,
                "HR": reach,
            },
        )

    def hurt(self, phase):
        """A flinch: the head snaps up and back and the body shudders."""
        hit = blend([(0.0, 0), (0.15, 1), (0.4, 0.4), (1.0, 0)], phase)
        shake = np.sin(2 * np.pi * phase * 4) * (1 - phase)
        return self.build(
            bob=-0.012 * hit,
            spine=(-0.12 * hit, 0.1 * shake),
            head=(-0.4 * hit, 0.2 * shake),
            tail=(0.3 * hit, 0.4 * shake),
            legs={
                "FL": (-0.15 * hit, 0.0, 0.0, 0.0),
                "FR": (-0.15 * hit, 0.0, 0.0, 0.0),
            },
        )


def sample(biped, name, fps=30):
    """Samples a clip. Returns times (K,), local translations (K, N, 3), rotations (K, N, 3, 3)."""
    clips = QUADRUPED_CLIPS if isinstance(biped, Quadruped) else CLIPS
    duration = clips[name][0]
    frames = max(2, int(round(duration * fps)))
    function = getattr(biped, name)
    times, translations, rotations = [], [], []
    for index in range(frames + 1):
        phase = index / frames
        t, r = function(phase)
        times.append(index / frames * duration)
        translations.append(t)
        rotations.append(r)
    return np.array(times), np.array(translations), np.array(rotations)
