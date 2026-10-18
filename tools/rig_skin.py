"""Skin weight repair for Tripo characters.

Tripo's auto-skinning leaves two kinds of damage that show as spikes and smeared textures the
moment a character moves:

  Orphans   A hundred or so vertices are bound entirely to "neutral_bone", a dummy joint that
            never moves. They stay in the T-pose while the body leaves, dragging long shards
            behind them. Each one takes the weights of its nearest properly skinned neighbours.
  Bridges   Cloth and hair that touch another limb in the bind pose are bound to both limbs, so
            a triangle between them is pulled apart when the limbs move. Skinning the mesh
            through every pose finds those triangles, and the weights around them are smoothed
            over the mesh until they move together.

Weights are kept per welded position, so the duplicate vertices at UV seams stay identical.
"""

import numpy as np
from scipy.sparse import coo_matrix, diags

WELD = 1e-5
MAX_INFLUENCES = 4


class SkinWeights:
    def __init__(self, rig):
        self.rig = rig
        count = len(rig.positions)
        self.joint_count = len(rig.joints)
        dense = np.zeros((count, self.joint_count))
        for k in range(MAX_INFLUENCES):
            np.add.at(dense, (np.arange(count), rig.skin_joints[:, k]), rig.skin_weights[:, k])
        keys = np.round(rig.positions / WELD).astype(np.int64)
        _, inverse = np.unique(keys, axis=0, return_inverse=True)
        self.weld = inverse.ravel()
        self.size = self.weld.max() + 1
        self.positions = np.zeros((self.size, 3))
        self.positions[self.weld] = rig.positions
        self.weights = np.zeros((self.size, self.joint_count))
        np.add.at(self.weights, self.weld, dense)
        self.weights /= np.bincount(self.weld, minlength=self.size)[:, None]
        corners = self.weld[rig.indices]
        edges = np.concatenate([corners[:, [0, 1]], corners[:, [1, 2]], corners[:, [2, 0]]])
        adjacency = coo_matrix(
            (np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(self.size, self.size)
        ).tocsr()
        self.adjacency = ((adjacency + adjacency.T) > 0).astype(float)
        self.average = diags(1.0 / np.maximum(np.asarray(self.adjacency.sum(1)).ravel(), 1)) @ (
            self.adjacency
        )
        self.corners = corners

    def fix_orphans(self, dummy_joint):
        """Gives vertices bound to the dummy joint the weights of their skinned neighbours."""
        orphan = self.weights[:, dummy_joint] > 0.5
        known = ~orphan
        self.weights[orphan] = 0.0
        for _ in range(100):
            if known.all():
                break
            sums = self.adjacency @ (self.weights * known[:, None])
            counts = self.adjacency @ known.astype(float)
            fresh = (~known) & (counts > 0)
            if not fresh.any():
                break
            self.weights[fresh] = sums[fresh] / counts[fresh][:, None]
            known |= fresh
        # Pieces that touch no skinned vertex at all, such as loose ornaments.
        skinned = np.nonzero(known)[0]
        for index in np.nonzero(~known)[0]:
            nearest = skinned[
                np.argmin(np.linalg.norm(self.positions[skinned] - self.positions[index], axis=1))
            ]
            self.weights[index] = self.weights[nearest]
        self.weights[:, dummy_joint] = 0.0
        self._normalise()
        return int(orphan.sum())

    def smooth(self, welded_mask, amount=0.5):
        blended = self.average @ self.weights
        self.weights[welded_mask] = (1 - amount) * self.weights[welded_mask] + amount * blended[
            welded_mask
        ]
        self._normalise()

    def _normalise(self):
        drop = np.argsort(-self.weights, axis=1)[:, MAX_INFLUENCES:]
        np.put_along_axis(self.weights, drop, 0.0, axis=1)
        self.weights /= self.weights.sum(axis=1, keepdims=True)

    def per_vertex(self):
        """Joint indices and weights, four per vertex, in the mesh's own vertex order."""
        expanded = self.weights[self.weld]
        joints = np.argsort(-expanded, axis=1)[:, :MAX_INFLUENCES]
        weights = np.take_along_axis(expanded, joints, axis=1)
        weights /= weights.sum(axis=1, keepdims=True)
        return joints, weights


def worst_stretch(rig, skin, stand_world, pose_worlds):
    """Worst stretch of every triangle over the move from the bind pose to the stand pose and
    from the stand pose through each of [pose_worlds]. Also returns the stand-pose positions."""
    joints, weights = skin.per_vertex()
    bind = rig.skin_matrices(stand_world)
    stand_positions = rig.deform(bind, weights, joints)
    worst = rig.triangle_stretch(stand_positions)
    inverse = np.linalg.inv(stand_world[rig.joints])
    for world in pose_worlds:
        matrices = world[rig.joints] @ inverse
        deformed = rig.deform(matrices, weights, joints, stand_positions)
        worst = np.maximum(worst, rig.triangle_stretch(deformed, stand_positions))
    return worst, stand_positions


def repair(rig, skin, stand_world, pose_worlds, limit, rounds, log=print):
    """Smooths the weights around stretched triangles until none exceeds [limit] or the rounds
    run out. Returns the final per-triangle stretch."""
    worst = None
    for index in range(rounds):
        worst, _ = worst_stretch(rig, skin, stand_world, pose_worlds)
        bad = np.nonzero(worst > limit)[0]
        log(
            "    round %2d: %5d triangles over %.1fx, worst %.1fx"
            % (index, len(bad), limit, worst.max())
        )
        if len(bad) == 0:
            break
        mask = np.zeros(skin.size, dtype=bool)
        mask[skin.corners[bad].ravel()] = True
        skin.smooth(mask)
    worst, _ = worst_stretch(rig, skin, stand_world, pose_worlds)
    return worst
