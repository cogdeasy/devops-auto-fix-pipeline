const request = require('supertest');
const app = require('../../app');
const userService = require('../../services/userService');

jest.mock('../../services/userService');

const mockUser = {
  id: 'usr_a1b2c3d4',
  name: 'Alice Johnson',
  email: 'alice@example.com',
  role: 'admin',
  createdAt: '2024-01-15T09:30:00.000Z',
};

beforeEach(() => {
  jest.clearAllMocks();
});

describe('User Controller', () => {
  // -------------------------------------------------------
  // GET /api/users — PASSING
  // -------------------------------------------------------
  describe('GET /api/users', () => {
    it('should return a paginated list of users', async () => {
      userService.findAll.mockResolvedValue({
        users: [mockUser],
        page: 1,
        limit: 20,
        total: 1,
      });

      const response = await request(app).get('/api/users');

      expect(response.status).toBe(200);
      expect(response.body.data).toHaveLength(1);
      expect(response.body.meta.total).toBe(1);
    });
  });

  // -------------------------------------------------------
  // GET /api/users/:id — 2 FAILING, 0 PASSING
  // -------------------------------------------------------
  describe('GET /api/users/:id', () => {
    it('should return user data', async () => {
      userService.findById.mockResolvedValue(mockUser);

      const response = await request(app).get('/api/users/usr_a1b2c3d4');

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('user');          // FAIL — should be 'data'
      expect(response.body.user).toBeDefined();              // FAIL — user is undefined
      expect(response.body.user.id).toBe('usr_a1b2c3d4');   // FAIL (cascading)
      expect(response.body.user.email).toBe('alice@example.com');
    });

    it('should return 404 for missing user', async () => {
      userService.findById.mockResolvedValue(null);

      const response = await request(app).get('/api/users/usr_nonexistent');

      expect(response.status).toBe(404);
      expect(response.body).toEqual({
        user: null,                                           // FAIL — key is now 'data'
        error: 'User not found',
      });
    });
  });

  // -------------------------------------------------------
  // PUT /api/users/:id — 1 FAILING, 0 PASSING
  // -------------------------------------------------------
  describe('PUT /api/users/:id', () => {
    it('should update user', async () => {
      const updatedUser = { ...mockUser, name: 'Alice Smith' };
      userService.updateById.mockResolvedValue(updatedUser);

      const response = await request(app)
        .put('/api/users/usr_a1b2c3d4')
        .send({ name: 'Alice Smith' });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('user');          // FAIL — should be 'data'
      expect(response.body.user.name).toBe('Alice Smith');   // FAIL — user is undefined
      expect(response.body.user.email).toBe('alice@example.com');
    });
  });

  // -------------------------------------------------------
  // DELETE /api/users/:id — PASSING
  // -------------------------------------------------------
  describe('DELETE /api/users/:id', () => {
    it('should delete a user and return 204', async () => {
      userService.deleteById.mockResolvedValue(true);

      const response = await request(app).delete('/api/users/usr_a1b2c3d4');

      expect(response.status).toBe(204);
      expect(response.body).toEqual({});
    });
  });
});
