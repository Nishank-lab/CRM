insert into role (role_id, role) values (1, 'ROLE_ADMIN'), (2, 'ROLE_USER'), (3, 'ROLE_MANAGER'), (4, 'ROLE_OWNER');
SET FOREIGN_KEY_CHECKS=0;
INSERT INTO category (category_id, category)
VALUES ('1', 'small'), ('2', 'medium'), ('3', 'big');

INSERT INTO customer (id, address, city, email, enabled, first_name, last_name, name, phone)
VALUES ('1', 'Small Street', 'Smallville', 'smallmail@mail.com', '1', 'SmallFN', 'SmallLN', 'Small INC', '123'),
  ('2', 'Medium Street', 'Midtown', 'midmail@mail.com', '1', 'MidFN', 'MidLN', 'Mid INC', '456'),
  ('3', 'Big Street', 'Big City', 'bigmail@mail.com', '1', 'BigFN', 'BigLN', 'Big INC', '789');

INSERT INTO customer_category (customer_id, category_id)
VALUES (1, 1), (2, 2), (3, 3);

INSERT INTO contract (id, begin_date, content, end_date, name, status, value, customer_id, user_id)
VALUES ('1', '2018-02-24 00:00:00', 'contract content', '2018-02-25 00:00:00', 'ContractName', 'PROPOSED', '100000.00', '2', '2');

SET FOREIGN_KEY_CHECKS=1;