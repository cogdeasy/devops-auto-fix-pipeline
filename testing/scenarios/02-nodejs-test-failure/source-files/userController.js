const userService = require('../../services/userService');
const { validateUserId, validateUserUpdate } = require('../../utils/validators');

/**
 * User Controller
 *
 * Handles HTTP requests for user CRUD operations.
 * All responses use a standardised envelope: { data, error?, meta? }
 */

// GET /api/users
const listUsers = async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const result = await userService.findAll({ page: Number(page), limit: Number(limit) });

    return res.status(200).json({
      data: result.users,
      meta: {
        page: result.page,
        limit: result.limit,
        total: result.total,
      },
    });
  } catch (err) {
    console.error('[UserController] listUsers error:', err.message);
    return res.status(500).json({ data: null, error: 'Internal server error' });
  }
};

// GET /api/users/:id
const getUserById = async (req, res) => {
  try {
    const { id } = req.params;

    if (!validateUserId(id)) {
      return res.status(400).json({ data: null, error: 'Invalid user ID format' });
    }

    const user = await userService.findById(id);

    if (!user) {
      return res.status(404).json({ data: null, error: 'User not found' });
    }

    return res.status(200).json({ data: user });
  } catch (err) {
    console.error('[UserController] getUserById error:', err.message);
    return res.status(500).json({ data: null, error: 'Internal server error' });
  }
};

// PUT /api/users/:id
const updateUser = async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    if (!validateUserId(id)) {
      return res.status(400).json({ data: null, error: 'Invalid user ID format' });
    }

    const validationErrors = validateUserUpdate(updates);
    if (validationErrors.length > 0) {
      return res.status(422).json({ data: null, errors: validationErrors });
    }

    const updatedUser = await userService.updateById(id, updates);

    if (!updatedUser) {
      return res.status(404).json({ data: null, error: 'User not found' });
    }

    return res.status(200).json({ data: updatedUser });
  } catch (err) {
    console.error('[UserController] updateUser error:', err.message);
    return res.status(500).json({ data: null, error: 'Internal server error' });
  }
};

// DELETE /api/users/:id
const deleteUser = async (req, res) => {
  try {
    const { id } = req.params;

    if (!validateUserId(id)) {
      return res.status(400).json({ data: null, error: 'Invalid user ID format' });
    }

    const deleted = await userService.deleteById(id);

    if (!deleted) {
      return res.status(404).json({ data: null, error: 'User not found' });
    }

    return res.status(204).send();
  } catch (err) {
    console.error('[UserController] deleteUser error:', err.message);
    return res.status(500).json({ data: null, error: 'Internal server error' });
  }
};

module.exports = { listUsers, getUserById, updateUser, deleteUser };
