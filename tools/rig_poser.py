"""Poses a Tripo skeleton by aiming bones, whatever its bind pose looks like.

Tripo's rigs come out of the bind pose with bent knees, one foot ahead of the other and arms
that are not on a straight line, and every bone has its own local axes. Fixed joint angles would
bend each model differently. This module aims bones at world directions instead: a bone's own
Y axis points at its child joint, so [Poser.aim] turns it onto the direction asked for and keeps
the roll of the bind pose.

A pose is a dictionary of requests, applied from the root down:
  rotate   {bone: 3x3 or (3x3, base_bone)}
                          extra world rotation applied after the parent's rotation, or after
                          the rotation of [base_bone] when one is given
  aim      {bone: vec3}   absolute world direction for the bone's Y axis
  offset   {bone: vec3}   world translation of the bone from its rest position
  feet     {side: (position, pitch)}  ankle target for two-bone IK, and sole pitch in radians
  legs     {side: (thigh, calf, foot)}  the bone names each entry of [feet] drives
Bones that are not mentioned inherit their parent's rotation.
"""

import numpy as np

from glb_rig import axis_angle


def arc(source, target):
    """Shortest rotation that turns unit vector [source] onto [target]."""
    source = source / np.linalg.norm(source)
    target = target / np.linalg.norm(target)
    axis = np.cross(source, target)
    sine = np.linalg.norm(axis)
    cosine = float(np.dot(source, target))
    if sine < 1e-9:
        if cosine > 0:
            return np.eye(3)
        helper = np.array([1.0, 0, 0]) if abs(source[0]) < 0.9 else np.array([0, 1.0, 0])
        return axis_angle(np.cross(source, helper), np.pi)
    return axis_angle(axis, np.arctan2(sine, cosine))


class Poser:
    def __init__(self, rig, forward):
        self.rig = rig
        self.up = np.array([0.0, 1.0, 0.0])
        self.forward = np.asarray(forward, dtype=float)
        self.forward /= np.linalg.norm(self.forward)
        self.left = np.cross(self.up, self.forward)
        self.rest_t, self.rest_r = rig.rest_pose()
        count = len(rig.names)
        self.world_r = np.zeros((count, 3, 3))
        self.world_p = np.zeros((count, 3))
        for index in rig.order:
            self._place_rest(index)
        self.bone_dir = self.world_r[:, :, 1]

    def _place_rest(self, index):
        parent = self.rig.parent[index]
        if parent < 0:
            self.world_r[index] = self.rest_r[index]
            self.world_p[index] = self.rest_t[index]
        else:
            self.world_r[index] = self.world_r[parent] @ self.rest_r[index]
            self.world_p[index] = self.world_p[parent] + self.world_r[parent] @ self.rest_t[index]

    def pos(self, name):
        """Rest world position of a bone."""
        return self.world_p[self.rig.find(name)]

    def pose(self, rotate=None, aim=None, offset=None, feet=None, legs=None):
        """Returns local translations (N, 3) and rotations (N, 3, 3) for the requested pose."""
        rig = self.rig
        rotate = rotate or {}
        aim = aim or {}
        offset = offset or {}
        feet = feet or {}
        legs = legs or {}
        count = len(rig.names)
        delta = np.tile(np.eye(3), (count, 1, 1))
        local_t = self.rest_t.copy()
        local_r = self.rest_r.copy()
        pose_r = np.zeros((count, 3, 3))
        pose_p = np.zeros((count, 3))
        solved = {}
        for index in rig.order:
            name = rig.names[index]
            parent = rig.parent[index]
            parent_delta = delta[parent] if parent >= 0 else np.eye(3)
            parent_r = pose_r[parent] if parent >= 0 else np.eye(3)
            parent_p = pose_p[parent] if parent >= 0 else np.zeros(3)
            if name in offset:
                local_t[index] = self.rest_t[index] + parent_r.T @ np.asarray(offset[name], float)
            pose_p[index] = parent_p + parent_r @ local_t[index]
            if name in solved:
                delta[index] = solved[name]
            elif name in aim:
                delta[index] = arc(self.bone_dir[index], np.asarray(aim[name], float))
            elif name in rotate:
                extra = rotate[name]
                if isinstance(extra, tuple):
                    extra, base = extra
                    delta[index] = extra @ delta[rig.find(base)]
                else:
                    delta[index] = extra @ parent_delta
            else:
                delta[index] = parent_delta
            for side, (thigh, calf, foot) in legs.items():
                if name == thigh and side in feet:
                    solved.update(self._solve_leg(index, pose_p[index], feet[side], legs[side]))
                    delta[index] = solved[name]
            pose_r[index] = delta[index] @ self.world_r[index]
            local_r[index] = parent_r.T @ pose_r[index]
        return local_t, local_r

    def _solve_leg(self, thigh, thigh_pos, target, names):
        """Two-bone IK: thigh and calf deltas that put the ankle on [target]."""
        rig = self.rig
        calf, foot = rig.find(names[1]), rig.find(names[2])
        upper = np.linalg.norm(self.world_p[calf] - self.world_p[thigh])
        lower = np.linalg.norm(self.world_p[foot] - self.world_p[calf])
        position, pitch = target
        reach = np.asarray(position, float) - thigh_pos
        distance = np.clip(np.linalg.norm(reach), 1e-6, (upper + lower) * 0.999)
        direction = reach / np.linalg.norm(reach)
        # Law of cosines gives the angle between the thigh and the hip-to-ankle line.
        cos_a = (upper * upper + distance * distance - lower * lower) / (2 * upper * distance)
        angle = np.arccos(np.clip(cos_a, -1, 1))
        # The knee sits in front of the hip-to-ankle line, in the plane that holds the leg.
        bend = self.forward - np.dot(self.forward, direction) * direction
        bend /= np.linalg.norm(bend)
        thigh_dir = direction * np.cos(angle) + bend * np.sin(angle)
        knee = thigh_pos + thigh_dir * upper
        calf_dir = np.asarray(position, float) - knee
        calf_dir /= np.linalg.norm(calf_dir)
        flat = np.array([self.forward[0], 0.0, self.forward[2]])
        rest_foot = self.bone_dir[foot]
        rest_pitch = np.arcsin(np.clip(rest_foot[1], -1, 1))
        foot_dir = flat * np.cos(rest_pitch) + self.up * np.sin(rest_pitch)
        foot_delta = axis_angle(self.left, -pitch) @ arc(rest_foot, foot_dir)
        return {
            names[0]: arc(self.bone_dir[thigh], thigh_dir),
            names[1]: arc(self.bone_dir[calf], calf_dir),
            names[2]: foot_delta,
        }

    def lean(self, angle):
        """Rotation that tips the body forward by [angle] radians."""
        return axis_angle(self.left, angle)

    def swing(self, angle):
        """Rotation that moves a downward limb forward by [angle] radians."""
        return axis_angle(self.left, -angle)

    def sway(self, angle):
        """Rotation that leans the body towards its left by [angle] radians."""
        return axis_angle(self.forward, -angle)

    def twist(self, angle):
        """Rotation about the vertical axis, positive turning the front towards the left."""
        return axis_angle(self.up, angle)

    def limb(self, side, abduct, forward, bend=0.0):
        """Upper arm or leg direction hanging down, spread by [abduct] and swung by [forward]."""
        out = self.left if side == "L" else -self.left
        down = -self.up * np.cos(abduct) + out * np.sin(abduct)
        direction = self.swing(forward) @ down
        return direction if bend == 0.0 else self.swing(bend) @ direction
